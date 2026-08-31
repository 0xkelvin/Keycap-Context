// SPDX-License-Identifier: Apache-2.0
import Foundation
import KeycapCore

@MainActor
final class DeviceConnectionController {
    var onEvent: ((DeviceEvent) -> Void)?
    var onStatusChange: ((DeviceStatus) -> Void)?

    private let preferredPath: String?
    private let autodetect: Bool
    private var serial: SerialDevice?
    private var reconnectTimer: Timer?
    private var pathRotation = SerialPathRotation()

    init(preferredPath: String?, autodetect: Bool) {
        self.preferredPath = preferredPath
        self.autodetect = autodetect
    }

    func start() {
        guard preferredPath != nil || autodetect else {
            onStatusChange?(.disabled)
            return
        }
        attemptConnection()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.attemptConnection() }
        }
    }

    func write(_ message: String) {
        serial?.write(message)
    }

    private func attemptConnection() {
        if serial != nil { return }
        let detectedPath = autodetect
            ? pathRotation.select(from: SerialDevice.autodetectCandidates()) : nil
        guard let path = preferredPath ?? detectedPath else {
            onStatusChange?(.disconnected)
            return
        }

        onStatusChange?(.connecting(path))
        let device = SerialDevice(path: path)
        device.onEvent = { [weak self, weak device] event in
            guard let self, self.serial === device else { return }
            self.pathRotation.rememberKeycap(path)
            if case .hello = event {
                // Opening a tty is not a successful Keycap connection. This
                // also prevents monitor-control USB modems from appearing
                // healthy while the actual board is disconnected.
                self.onStatusChange?(.connected(path))
            }
            self.onEvent?(event)
        }
        device.onDisconnect = { [weak self, weak device] error in
            guard let self, self.serial === device else { return }
            self.serial = nil
            if self.preferredPath == nil, !self.pathRotation.isRemembered(path) {
                self.pathRotation.advance()
            }
            if let error {
                fputs("Keycap serial \(path) disconnected: \(error.localizedDescription)\n", stderr)
            }
            self.onStatusChange?(error.map { .failed($0.localizedDescription) } ?? .disconnected)
        }
        do {
            try device.openDevice()
            serial = device
        } catch {
            if preferredPath == nil { pathRotation.advance() }
            onStatusChange?(.failed(error.localizedDescription))
        }
    }
}

/// Cycles through all serial candidates instead of selecting the first path on
/// every retry. Developer boards and debug probes commonly expose more than
/// one `cu.usbmodem` device; a silent non-Keycap port must not starve the real
/// board forever.
struct SerialPathRotation {
    private var cursor = 0
    private var rememberedKeycapPath: String?

    mutating func select(from candidates: [String]) -> String? {
        let candidates = Array(Set(candidates)).sorted()
        guard !candidates.isEmpty else { return nil }
        if let rememberedKeycapPath, candidates.contains(rememberedKeycapPath) {
            return rememberedKeycapPath
        }
        return candidates[cursor % candidates.count]
    }

    mutating func rememberKeycap(_ path: String) {
        rememberedKeycapPath = path
    }

    func isRemembered(_ path: String) -> Bool {
        rememberedKeycapPath == path
    }

    mutating func advance() {
        cursor = cursor == Int.max ? 0 : cursor + 1
    }
}
