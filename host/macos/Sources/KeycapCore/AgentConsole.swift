// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum AgentActivityState: String, Codable, CaseIterable, Equatable, Sendable {
    case idle
    case working
    case waiting
    case completed
    case failed
}

public enum AgentControlAction: String, Codable, CaseIterable, Equatable, Sendable {
    case focus
    case interrupt
    case resume
    case cancel
    case markRead
    case unassign
}

public struct AgentStatusUpdate: Codable, Equatable, Sendable {
    public let session: String
    public let source: String
    public let project: String?
    public let context: String?
    public let state: AgentActivityState
    public let summary: String?
    public let clientApp: String?
    public let preferredKey: Int?

    public init(
        session: String,
        source: String,
        project: String? = nil,
        context: String? = nil,
        state: AgentActivityState,
        summary: String? = nil,
        clientApp: String? = nil,
        preferredKey: Int? = nil
    ) {
        self.session = session
        self.source = source
        self.project = project
        self.context = context
        self.state = state
        self.summary = summary
        self.clientApp = clientApp
        self.preferredKey = preferredKey
    }
}

public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { session }
    public let session: String
    public var source: String
    public var project: String?
    public var context: String?
    public var state: AgentActivityState
    public var summary: String?
    public var clientApp: String?
    public var assignedKey: Int
    public var updatedAt: Date
    public var unread: Bool
    public var destructiveApproval: Bool
}

public struct AgentControlCommand: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let session: String
    public let action: AgentControlAction
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        session: String,
        action: AgentControlAction,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.action = action
        self.createdAt = createdAt
    }
}

public enum AuditEventKind: String, Codable, Equatable, Sendable {
    case status
    case request
    case selected
    case cancelled
    case control
}

public struct AgentAuditEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let session: String
    public let source: String
    public let kind: AuditEventKind
    public let summary: String
    public let risk: RequestRisk?
}

public struct AgentConsoleSnapshot: Codable, Equatable, Sendable {
    public var sessions: [AgentSession]
    public var history: [AgentAuditEvent]

    public init(sessions: [AgentSession] = [], history: [AgentAuditEvent] = []) {
        self.sessions = sessions
        self.history = history
    }
}

@MainActor
public final class AgentConsole {
    public static let keyCount = 4
    public static let historyLimit = 500

    public var onChange: (() -> Void)?
    public private(set) var sessions: [AgentSession]
    public private(set) var history: [AgentAuditEvent]
    private var pendingCommands: [String: [AgentControlCommand]] = [:]

    public init(snapshot: AgentConsoleSnapshot = AgentConsoleSnapshot()) {
        sessions = snapshot.sessions.filter { (1...Self.keyCount).contains($0.assignedKey) }
        history = Array(snapshot.history.suffix(Self.historyLimit))
        normalizeAssignments()
    }

    public var slots: [AgentSession?] {
        (1...Self.keyCount).map { key in
            sessions.first(where: { $0.assignedKey == key })
        }
    }

    public var snapshot: AgentConsoleSnapshot {
        AgentConsoleSnapshot(sessions: sessions, history: history)
    }

    @discardableResult
    public func update(_ update: AgentStatusUpdate, now: Date = Date()) -> AgentSession? {
        guard isValid(update) else { return nil }
        let index: Int
        if let existing = sessions.firstIndex(where: { $0.session == update.session }) {
            index = existing
        } else {
            let key = allocateKey(preferred: update.preferredKey)
            if let occupied = sessions.firstIndex(where: { $0.assignedKey == key }) {
                sessions.remove(at: occupied)
            }
            sessions.append(AgentSession(
                session: update.session,
                source: update.source,
                project: update.project,
                context: update.context,
                state: update.state,
                summary: update.summary,
                clientApp: update.clientApp,
                assignedKey: key,
                updatedAt: now,
                unread: update.state == .completed || update.state == .failed,
                destructiveApproval: false
            ))
            index = sessions.count - 1
        }

        sessions[index].source = update.source
        sessions[index].project = update.project ?? sessions[index].project
        sessions[index].context = update.context ?? sessions[index].context
        sessions[index].state = update.state
        sessions[index].summary = update.summary ?? sessions[index].summary
        sessions[index].clientApp = update.clientApp ?? sessions[index].clientApp
        sessions[index].updatedAt = now
        if update.state == .completed || update.state == .failed {
            sessions[index].unread = true
        } else if update.state == .working || update.state == .waiting {
            sessions[index].unread = false
        }
        if let preferred = update.preferredKey, (1...Self.keyCount).contains(preferred) {
            assign(session: update.session, to: preferred)
        }
        appendHistory(
            session: update.session, source: update.source, kind: .status,
            summary: update.summary ?? update.state.rawValue, risk: nil, now: now
        )
        changed()
        return sessions.first(where: { $0.session == update.session })
    }

    public func noteRequest(_ request: AgentRequest, now: Date = Date()) {
        let sessionID = request.session ?? request.id
        _ = update(AgentStatusUpdate(
            session: sessionID,
            source: request.source,
            project: request.project,
            context: request.context,
            state: .waiting,
            summary: request.title,
            clientApp: request.clientApp
        ), now: now)
        if let index = sessions.firstIndex(where: { $0.session == sessionID }) {
            sessions[index].destructiveApproval = request.risk == .destructive
        }
        appendHistory(
            session: sessionID, source: request.source, kind: .request,
            summary: request.title, risk: request.risk, now: now
        )
        changed()
    }

    public func noteResolution(
        request: AgentRequest,
        resolution: AgentResolution,
        now: Date = Date()
    ) {
        let sessionID = request.session ?? request.id
        guard let index = sessions.firstIndex(where: { $0.session == sessionID }) else { return }
        sessions[index].destructiveApproval = false
        sessions[index].updatedAt = now
        switch resolution {
        case .selected(let response):
            sessions[index].state = .working
            sessions[index].summary = "Selected \(response.choiceId)"
            appendHistory(
                session: sessionID, source: request.source, kind: .selected,
                summary: "\(request.title): \(response.choiceId)", risk: request.risk, now: now
            )
        case .cancelled(let cancellation):
            sessions[index].state = cancellation.reason == "timeout" ? .failed : .working
            sessions[index].summary = cancellation.reason ?? "Returned to agent"
            appendHistory(
                session: sessionID, source: request.source, kind: .cancelled,
                summary: "\(request.title): \(cancellation.reason ?? "cancelled")",
                risk: request.risk, now: now
            )
        }
        changed()
    }

    @discardableResult
    public func enqueueControl(key: Int, action: AgentControlAction) -> AgentControlCommand? {
        guard let index = sessions.firstIndex(where: { $0.assignedKey == key }) else { return nil }
        if action == .markRead {
            sessions[index].unread = false
            if sessions[index].state == .completed { sessions[index].state = .idle }
        }
        let command = AgentControlCommand(session: sessions[index].session, action: action)
        pendingCommands[command.session, default: []].append(command)
        appendHistory(
            session: command.session, source: sessions[index].source, kind: .control,
            summary: action.rawValue, risk: nil, now: command.createdAt
        )
        changed()
        return command
    }

    public func takeCommands(session: String) -> [AgentControlCommand] {
        let commands = pendingCommands.removeValue(forKey: session) ?? []
        if !commands.isEmpty { changed() }
        return commands
    }

    public func session(forKey key: Int) -> AgentSession? {
        sessions.first(where: { $0.assignedKey == key })
    }

    @discardableResult
    public func remove(session: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.session == session }) else {
            return false
        }
        pendingCommands.removeValue(forKey: session)
        sessions.remove(at: index)
        changed()
        return true
    }

    private func isValid(_ update: AgentStatusUpdate) -> Bool {
        !update.session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !update.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        update.session.utf8.count <= 512 && update.source.utf8.count <= 128 &&
        (update.summary?.utf8.count ?? 0) <= 4_096 &&
        (update.preferredKey.map { (1...Self.keyCount).contains($0) } ?? true)
    }

    private func allocateKey(preferred: Int?) -> Int {
        if let preferred, (1...Self.keyCount).contains(preferred),
           !sessions.contains(where: { $0.assignedKey == preferred }) {
            return preferred
        }
        if let free = (1...Self.keyCount).first(where: { key in
            !sessions.contains(where: { $0.assignedKey == key })
        }) { return free }
        return sessions.min(by: { replacementRank($0) < replacementRank($1) })?.assignedKey ?? 1
    }

    private func replacementRank(_ session: AgentSession) -> (Int, Date) {
        let priority: Int
        switch session.state {
        case .idle: priority = 0
        case .completed, .failed: priority = 1
        case .working: priority = 2
        case .waiting: priority = 3
        }
        return (priority, session.updatedAt)
    }

    private func assign(session: String, to key: Int) {
        guard let sourceIndex = sessions.firstIndex(where: { $0.session == session }) else { return }
        if let otherIndex = sessions.firstIndex(where: {
            $0.assignedKey == key && $0.session != session
        }) {
            let oldKey = sessions[sourceIndex].assignedKey
            sessions[otherIndex].assignedKey = oldKey
        }
        sessions[sourceIndex].assignedKey = key
    }

    private func normalizeAssignments() {
        var used: Set<Int> = []
        sessions = sessions.sorted { $0.updatedAt > $1.updatedAt }.filter { session in
            guard !used.contains(session.assignedKey), used.count < Self.keyCount else { return false }
            used.insert(session.assignedKey)
            return true
        }
    }

    private func appendHistory(
        session: String,
        source: String,
        kind: AuditEventKind,
        summary: String,
        risk: RequestRisk?,
        now: Date
    ) {
        history.append(AgentAuditEvent(
            id: UUID().uuidString,
            timestamp: now,
            session: session,
            source: source,
            kind: kind,
            summary: String(summary.prefix(4_096)),
            risk: risk
        ))
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    private func changed() { onChange?() }
}
