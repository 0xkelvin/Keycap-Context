// SPDX-License-Identifier: Apache-2.0
import Foundation
import KeycapCore
import Network

final class LocalHTTPServer {
    enum State: Equatable {
        case starting
        case ready(UInt16)
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private let port: NWEndpoint.Port
    private let token: String
    private let broker: RequestBroker
    private let agentConsole: AgentConsole
    private let healthProvider: @MainActor () -> HealthSnapshot
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ai.keycap.http")
    private let bindingLock = NSLock()
    private var requestBindings: [ObjectIdentifier: String] = [:]

    @MainActor
    init(
        port: UInt16 = 47_821,
        token: String,
        broker: RequestBroker,
        agentConsole: AgentConsole,
        healthProvider: @escaping @MainActor () -> HealthSnapshot
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }
        guard !token.isEmpty else { throw ServerError.missingToken }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"), port: endpointPort
        )
        self.port = endpointPort
        self.token = token
        self.broker = broker
        self.agentConsole = agentConsole
        self.healthProvider = healthProvider
        self.listener = try NWListener(using: parameters)
    }

    func start() {
        onStateChange?(.starting)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, port] state in
            if case .ready = state {
                print("Keycap broker listening on http://127.0.0.1:\(port)")
                DispatchQueue.main.async { self?.onStateChange?(.ready(port.rawValue)) }
            } else if case .failed(let error) = state {
                fputs("Keycap HTTP listener failed: \(error)\n", stderr)
                DispatchQueue.main.async { self?.onStateChange?(.failed(error.localizedDescription)) }
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state {
                self.clientDisconnected(connection)
            } else if case .cancelled = state {
                self.clientDisconnected(connection)
            }
        }
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, complete, error in
            guard let self else { return }
            var updated = buffer
            if let data { updated.append(data) }
            if updated.count > 1_048_576 {
                self.respond(connection, status: "413 Payload Too Large", body: Data())
                return
            }
            if let request = HTTPRequest.parse(updated) {
                self.handle(request, connection: connection)
            } else if complete || error != nil {
                self.respond(connection, status: "400 Bad Request", body: Data())
            } else {
                self.read(connection, buffer: updated)
            }
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        switch RequestAuthorization.evaluate(headers: request.headers, token: token) {
        case .allowed:
            break
        case .untrustedHost, .crossSite:
            respond(connection, status: "403 Forbidden", body: Data())
            return
        case .unauthorized:
            respond(
                connection, status: "401 Unauthorized", body: Data(),
                extraHeaders: ["WWW-Authenticate": "Bearer realm=\"keycap\""]
            )
            return
        }
        if request.method == "GET" && request.path == "/health" {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection,
                      let body = try? JSONEncoder().encode(self.healthProvider()) else { return }
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        if request.method == "GET" && request.path == "/v1/capabilities" {
            let body = (try? JSONEncoder().encode(BrokerCapabilities())) ?? Data()
            respond(connection, status: "200 OK", body: body)
            return
        }

        if request.method == "GET" && request.path == "/v1/sessions" {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                let body = (try? JSONEncoder.keycap.encode(self.agentConsole.sessions)) ?? Data()
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        if request.method == "GET" && request.path == "/v1/history" {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                let body = (try? JSONEncoder.keycap.encode(self.agentConsole.history)) ?? Data()
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        if request.method == "POST" && request.path == "/v1/sessions/status",
           let update = try? JSONDecoder.keycap.decode(AgentStatusUpdate.self, from: request.body) {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                if let session = self.agentConsole.update(update),
                   let body = try? JSONEncoder.keycap.encode(session) {
                    self.respond(connection, status: "200 OK", body: body)
                } else {
                    self.respond(connection, status: "422 Unprocessable Entity", body: Data())
                }
            }
            return
        }

        if request.method == "POST" && request.path == "/v1/sessions/control",
           let control = try? JSONDecoder.keycap.decode(SessionControlRequest.self, from: request.body) {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                guard let session = self.agentConsole.sessions.first(where: {
                          $0.session == control.session
                      }), let command = self.agentConsole.enqueueControl(
                          key: session.assignedKey, action: control.action
                      ), let body = try? JSONEncoder.keycap.encode(command) else {
                    self.respond(connection, status: "404 Not Found", body: Data())
                    return
                }
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        if request.method == "DELETE" && request.path.hasPrefix("/v1/sessions/") {
            let encoded = String(request.path.dropFirst("/v1/sessions/".count))
            let session = encoded.removingPercentEncoding ?? encoded
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                if self.agentConsole.remove(session: session) {
                    self.respond(connection, status: "200 OK", body: Data("{}".utf8))
                } else {
                    self.respond(connection, status: "404 Not Found", body: Data())
                }
            }
            return
        }

        if request.method == "GET", let session = commandSession(from: request.path) {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                let commands = self.agentConsole.takeCommands(session: session)
                let body = (try? JSONEncoder.keycap.encode(commands)) ?? Data()
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        if request.method == "DELETE" && request.path.hasPrefix("/v1/requests/") {
            let encoded = String(request.path.dropFirst("/v1/requests/".count))
            let requestID = encoded.removingPercentEncoding ?? encoded
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                if let cancellation = self.broker.cancel(
                    requestID: requestID, reason: "adapter-cancelled"
                ), let body = try? JSONEncoder().encode(cancellation) {
                    self.respond(connection, status: "200 OK", body: body)
                } else {
                    self.respond(connection, status: "404 Not Found", body: Data())
                }
            }
            return
        }

        if request.method == "POST" && request.path == "/v1/sessions/cancel",
           let cancellation = try? JSONDecoder().decode(SessionCancellation.self, from: request.body) {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                let count = self.broker.cancel(
                    session: cancellation.session, reason: "session-ended"
                )
                let body = (try? JSONEncoder().encode(CancellationCount(cancelled: count))) ?? Data()
                self.respond(connection, status: "200 OK", body: body)
            }
            return
        }

        guard request.method == "POST", request.path == "/v1/requests/wait",
              let agentRequest = try? JSONDecoder().decode(AgentRequest.self, from: request.body) else {
            respond(connection, status: "400 Bad Request", body: Data())
            return
        }

        bind(connection, requestID: agentRequest.id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = self.broker.submitResult(agentRequest) { [weak self, weak connection] resolution in
                guard let self else { return }
                self.agentConsole.noteResolution(request: agentRequest, resolution: resolution)
                guard let connection else { return }
                self.unbind(connection)
                let body: Data?
                switch resolution {
                case .selected(let response):
                    body = try? JSONEncoder().encode(response)
                case .cancelled(let cancellation):
                    body = try? JSONEncoder().encode(cancellation)
                }
                guard let body else { return }
                self.respond(connection, status: "200 OK", body: body)
            }
            switch result {
            case .accepted:
                self.agentConsole.noteRequest(agentRequest)
                break
            case .invalid:
                self.unbind(connection)
                self.respond(connection, status: "422 Unprocessable Entity", body: Data())
            case .duplicate:
                self.unbind(connection)
                self.respond(connection, status: "409 Conflict", body: Data())
            case .paused:
                self.unbind(connection)
                self.respond(connection, status: "503 Service Unavailable", body: Data())
            case .full:
                self.unbind(connection)
                self.respond(connection, status: "429 Too Many Requests", body: Data())
            }
        }
    }

    private func commandSession(from path: String) -> String? {
        let prefix = "/v1/sessions/"
        let suffix = "/commands"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
        let encoded = String(path.dropFirst(prefix.count).dropLast(suffix.count))
        guard !encoded.isEmpty else { return nil }
        return encoded.removingPercentEncoding
    }

    private func bind(_ connection: NWConnection, requestID: String) {
        bindingLock.lock()
        requestBindings[ObjectIdentifier(connection)] = requestID
        bindingLock.unlock()
    }

    private func unbind(_ connection: NWConnection) {
        bindingLock.lock()
        requestBindings.removeValue(forKey: ObjectIdentifier(connection))
        bindingLock.unlock()
    }

    private func clientDisconnected(_ connection: NWConnection) {
        bindingLock.lock()
        let requestID = requestBindings.removeValue(forKey: ObjectIdentifier(connection))
        bindingLock.unlock()
        guard let requestID else { return }
        Task { @MainActor [weak self] in
            _ = self?.broker.cancel(requestID: requestID, reason: "client-disconnected")
        }
    }

    private func respond(
        _ connection: NWConnection,
        status: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) {
        let header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: application/json\r\n" +
            extraHeaders.map { "\($0.key): \($0.value)\r\n" }.sorted().joined() +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    enum ServerError: Error, CustomStringConvertible {
        case invalidPort
        case missingToken

        var description: String {
            switch self {
            case .invalidPort: return "Invalid broker port"
            case .missingToken: return "The broker refuses to start without a token"
            }
        }
    }
}

private extension JSONEncoder {
    static var keycap: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var keycap: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct SessionCancellation: Decodable {
    let session: String
}

private struct SessionControlRequest: Decodable {
    let session: String
    let action: AgentControlAction
}

private struct CancellationCount: Encodable {
    let cancelled: Int
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
    let headers: [String: String]

    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { return nil }

        var contentLength = 0
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                let name = pair[0].lowercased()
                let value = pair[1].trimmingCharacters(in: .whitespaces)
                headers[name] = value
                if name == "content-length" {
                    contentLength = Int(value) ?? -1
                }
            }
        }
        guard (0...1_048_576).contains(contentLength) else { return nil }

        let bodyStart = headerRange.upperBound
        guard contentLength <= data.count - bodyStart else { return nil }
        return HTTPRequest(
            method: requestLine[0],
            path: requestLine[1],
            body: data.subdata(in: bodyStart..<(bodyStart + contentLength)),
            headers: headers
        )
    }
}
