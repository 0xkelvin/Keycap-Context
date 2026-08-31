// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import KeycapCore

final class SerialDevice {
    var onEvent: ((DeviceEvent) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private let path: String
    private let queue = DispatchQueue(label: "ai.keycap.serial")
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var heartbeat: DispatchSourceTimer?
    private var receiveBuffer = Data()
    private var didDisconnect = false
    private var receivedHello = false
    private var lastDeviceResponse = DispatchTime.now().uptimeNanoseconds
    private var heartbeatRecovery = HeartbeatRecovery()

    private static let responseTimeoutNanoseconds: UInt64 = 6_000_000_000

    init(path: String) {
        self.path = path
    }

    deinit {
        heartbeat?.cancel()
        source?.cancel()
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    func openDevice() throws {
        descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else { throw SerialError.openFailed(path) }

        // Configuration can fail for a device that disappears between
        // discovery and tcsetattr. Do not leak its descriptor on that path.
        var configured = false
        defer {
            if !configured, descriptor >= 0 {
                Darwin.close(descriptor)
                descriptor = -1
            }
        }

        var configuration = termios()
        guard tcgetattr(descriptor, &configuration) == 0 else {
            throw SerialError.configurationFailed
        }
        // Configure every relevant flag explicitly. `cfmakeraw` preserves
        // platform-specific modem/flow-control state, which can leave a CMSIS-
        // DAP UART able to receive button traffic while its transmit direction
        // never reaches the board.
        configuration.c_iflag = 0
        configuration.c_oflag = 0
        configuration.c_lflag = 0
        configuration.c_cflag = tcflag_t(CS8 | CLOCAL | CREAD)
        guard cfsetspeed(&configuration, speed_t(B115200)) == 0,
              tcsetattr(descriptor, TCSANOW, &configuration) == 0,
              tcflush(descriptor, TCIOFLUSH) == 0 else {
            throw SerialError.configurationFailed
        }
        configured = true

        let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        readSource.setEventHandler { [weak self] in self?.readAvailable() }
        readSource.resume()
        source = readSource
        didDisconnect = false
        receivedHello = false
        heartbeatRecovery.reset()
        receiveBuffer.removeAll(keepingCapacity: true)
        lastDeviceResponse = DispatchTime.now().uptimeNanoseconds
        startHeartbeat()
        write("PING\n")
        print("Keycap device connected at \(path)")
    }

    func write(_ message: String) {
        guard descriptor >= 0 else { return }
        let bytes = Array(message.utf8)
        queue.async { [weak self] in
            guard let self else { return }
            self.writeNow(bytes)
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            let elapsed = DispatchTime.now().uptimeNanoseconds &- self.lastDeviceResponse
            switch self.heartbeatRecovery.evaluate(
                timedOut: elapsed >= Self.responseTimeoutNanoseconds
            ) {
            case .disconnect:
                self.signalDisconnect(SerialError.unresponsive)
                return
            case .probe:
                // A Mac sleep produces a long apparent heartbeat gap. Probe
                // the existing descriptor first; closing/reopening this
                // board's SAMD11 CDC bridge can wedge its transmit direction.
                self.lastDeviceResponse = DispatchTime.now().uptimeNanoseconds
                self.receivedHello = false
                self.writeNow(Array("PING\n".utf8))
                return
            case .normal:
                break
            }
            let command = self.receivedHello ? "KEEPALIVE\n" : "PING\n"
            self.writeNow(Array(command.utf8))
        }
        timer.resume()
        heartbeat = timer
    }

    private func writeNow(_ bytes: [UInt8]) {
        guard descriptor >= 0 else { return }
        let error = bytes.withUnsafeBytes { raw -> Error? in
            guard let base = raw.baseAddress else { return nil }
            var written = 0
            while written < raw.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: written),
                    raw.count - written
                )
                if count > 0 {
                    written += count
                    continue
                }
                if count < 0 && errno == EINTR { continue }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    var readiness = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    let result = Darwin.poll(&readiness, 1, 1_000)
                    if result > 0 { continue }
                    let code = result == 0 ? ETIMEDOUT : errno
                    return POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                let code = count == 0 ? EIO : errno
                return POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            return nil
        }
        if let error { signalDisconnect(error) }
    }

    private func readAvailable() {
        var bytes = [UInt8](repeating: 0, count: 512)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
        guard count > 0 else {
            signalDisconnect(count < 0 ? POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) : nil)
            return
        }
        receiveBuffer.append(contentsOf: bytes.prefix(count))

        while let newline = receiveBuffer.firstIndex(of: 0x0a) {
            let lineData = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "ALIVE" {
                lastDeviceResponse = DispatchTime.now().uptimeNanoseconds
                heartbeatRecovery.acknowledge()
                continue
            }
            guard let event = DeviceProtocolV1.parse(line) else { continue }
            if event.provesDeviceIsListening {
                receivedHello = true
                lastDeviceResponse = DispatchTime.now().uptimeNanoseconds
                heartbeatRecovery.acknowledge()
            }
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }
    }

    private func signalDisconnect(_ error: Error?) {
        guard !didDisconnect else { return }
        didDisconnect = true
        heartbeat?.cancel()
        heartbeat = nil
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        DispatchQueue.main.async { [weak self] in self?.onDisconnect?(error) }
    }

    static func autodetectCandidates() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return entries
            .filter { $0.hasPrefix("cu.usbmodem") }
            .sorted()
            .map { "/dev/\($0)" }
    }

    enum SerialError: Error, LocalizedError, CustomStringConvertible {
        case openFailed(String)
        case configurationFailed
        case unresponsive

        var description: String {
            switch self {
            case .openFailed(let path): return "Could not open serial device \(path)"
            case .configurationFailed: return "Could not configure serial device"
            case .unresponsive: return "Serial device stopped acknowledging heartbeats"
            }
        }


        var errorDescription: String? { description }
    }
}

struct HeartbeatRecovery {
    enum Action: Equatable { case normal, probe, disconnect }
    private var awaitingProbeReply = false

    mutating func evaluate(timedOut: Bool) -> Action {
        guard timedOut else { return .normal }
        if awaitingProbeReply { return .disconnect }
        awaitingProbeReply = true
        return .probe
    }

    mutating func acknowledge() {
        awaitingProbeReply = false
    }

    mutating func reset() {
        awaitingProbeReply = false
    }
}
