// SPDX-License-Identifier: Apache-2.0
import Foundation

public struct Choice: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct AgentRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: String
    public let session: String?
    public let project: String?
    public let context: String?
    public let kind: String
    public let title: String
    public let detail: String?
    public let choices: [Choice]
    public let allowsMultiple: Bool?
    public let progress: RequestProgress?
    public let timeoutSeconds: Double?
    public let accentColor: String?
    public let risk: RequestRisk?
    public let clientApp: String?

    public init(
        id: String = UUID().uuidString,
        source: String,
        session: String? = nil,
        project: String? = nil,
        context: String? = nil,
        kind: String,
        title: String,
        detail: String? = nil,
        choices: [Choice],
        allowsMultiple: Bool? = nil,
        progress: RequestProgress? = nil,
        timeoutSeconds: Double? = nil,
        accentColor: String? = nil,
        risk: RequestRisk? = nil,
        clientApp: String? = nil
    ) {
        self.id = id
        self.source = source
        self.session = session
        self.project = project
        self.context = context
        self.kind = kind
        self.title = title
        self.detail = detail
        self.choices = choices
        self.allowsMultiple = allowsMultiple
        self.progress = progress
        self.timeoutSeconds = timeoutSeconds
        self.accentColor = accentColor
        self.risk = risk
        self.clientApp = clientApp
    }
}

public enum RequestRisk: String, Codable, Equatable, Sendable {
    case standard
    case destructive
}

public struct RequestProgress: Codable, Equatable, Sendable {
    public let current: Int
    public let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }
}

public struct AgentResponse: Codable, Equatable, Sendable {
    public let requestId: String
    public let choiceId: String
    public let choiceIndex: Int
    public let choiceIds: [String]

    public init(
        requestId: String,
        choiceId: String,
        choiceIndex: Int,
        choiceIds: [String]? = nil
    ) {
        self.requestId = requestId
        self.choiceId = choiceId
        self.choiceIndex = choiceIndex
        self.choiceIds = choiceIds ?? [choiceId]
    }
}

public struct AgentCancellation: Codable, Equatable, Sendable {
    public let requestId: String
    public let cancelled: Bool
    public let reason: String?

    public init(requestId: String, reason: String? = nil) {
        self.requestId = requestId
        self.cancelled = true
        self.reason = reason
    }
}

public enum AgentResolution: Equatable, Sendable {
    case selected(AgentResponse)
    case cancelled(AgentCancellation)
}

public struct BrokerCapabilities: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let maxChoices: Int
    public let supportsMultiSelect: Bool
    public let supportsPagination: Bool
    public let supportsCancellationReasons: Bool
    public let deviceProtocolVersions: [Int]
    public let maxQueueDepth: Int
    public let supportsAgentConsole: Bool
    public let supportsContextProfiles: Bool

    public init(
        apiVersion: Int = 1,
        maxChoices: Int = 16,
        supportsMultiSelect: Bool = true,
        supportsPagination: Bool = true,
        supportsCancellationReasons: Bool = true,
        deviceProtocolVersions: [Int] = [1, 2, 3],
        maxQueueDepth: Int = 64,
        supportsAgentConsole: Bool = true,
        supportsContextProfiles: Bool = true
    ) {
        self.apiVersion = apiVersion
        self.maxChoices = maxChoices
        self.supportsMultiSelect = supportsMultiSelect
        self.supportsPagination = supportsPagination
        self.supportsCancellationReasons = supportsCancellationReasons
        self.deviceProtocolVersions = deviceProtocolVersions
        self.maxQueueDepth = maxQueueDepth
        self.supportsAgentConsole = supportsAgentConsole
        self.supportsContextProfiles = supportsContextProfiles
    }
}
