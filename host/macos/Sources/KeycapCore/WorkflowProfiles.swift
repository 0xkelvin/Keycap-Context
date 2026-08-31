// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum WorkflowActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case focusAgent
    case interruptAgent
    case openURL
    case shellCommand

    public var displayName: String {
        switch self {
        case .none: return "No action"
        case .focusAgent: return "Focus agent"
        case .interruptAgent: return "Interrupt agent"
        case .openURL: return "Open URL"
        case .shellCommand: return "Run command"
        }
    }
}

public struct WorkflowAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var kind: WorkflowActionKind
    public var value: String
    public var requiresConfirmation: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        kind: WorkflowActionKind = .none,
        value: String = "",
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct ContextProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var applicationBundleIdentifier: String
    public var projectContains: String
    public var actions: [WorkflowAction]

    public init(
        id: String = UUID().uuidString,
        name: String,
        applicationBundleIdentifier: String = "",
        projectContains: String = "",
        actions: [WorkflowAction] = []
    ) {
        self.id = id
        self.name = name
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.projectContains = projectContains
        self.actions = Array(actions.prefix(4))
            + (actions.count < 4 ? (actions.count..<4).map {
                WorkflowAction(label: "Key \($0 + 1)")
            } : [])
    }

    public func matches(applicationBundleIdentifier: String?, project: String?) -> Bool {
        let appRule = self.applicationBundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let projectRule = projectContains.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appRule.isEmpty || !projectRule.isEmpty else { return true }
        let appMatches = appRule.isEmpty || applicationBundleIdentifier?
            .localizedCaseInsensitiveContains(appRule) == true
        let projectMatches = projectRule.isEmpty || project?
            .localizedCaseInsensitiveContains(projectRule) == true
        return appMatches && projectMatches
    }
}

public enum ContextProfileMatcher {
    public static func match(
        _ profiles: [ContextProfile],
        applicationBundleIdentifier: String?,
        project: String?
    ) -> ContextProfile? {
        profiles.first {
            $0.matches(
                applicationBundleIdentifier: applicationBundleIdentifier,
                project: project
            )
        }
    }
}
