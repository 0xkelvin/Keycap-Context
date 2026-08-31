// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation
import KeycapCore

@MainActor
final class AgentConsoleStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var history: [AgentAuditEvent] = []

    let console: AgentConsole
    let fileURL: URL
    var onChange: (() -> Void)?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        let snapshot = Self.load(from: self.fileURL) ?? AgentConsoleSnapshot()
        console = AgentConsole(snapshot: snapshot)
        refresh()
        console.onChange = { [weak self] in
            self?.refresh()
            self?.save()
            self?.onChange?()
        }
    }

    private func refresh() {
        sessions = console.sessions.sorted { $0.assignedKey < $1.assignedKey }
        history = Array(console.history.reversed())
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(console.snapshot).write(to: fileURL, options: .atomic)
        } catch {
            fputs("Could not save Keycap agent activity: \(error)\n", stderr)
        }
    }

    private static func load(from url: URL) -> AgentConsoleSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentConsoleSnapshot.self, from: data)
    }

    private static func defaultURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent("Keycap Context/agent-console.json")
    }
}
