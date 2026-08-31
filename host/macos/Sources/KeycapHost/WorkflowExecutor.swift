// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation
import KeycapCore

@MainActor
final class WorkflowExecutor {
    var onAgentControl: ((Int, AgentControlAction) -> Void)?

    func execute(_ action: WorkflowAction, physicalKey: Int) {
        switch action.kind {
        case .none:
            break
        case .focusAgent:
            onAgentControl?(slot(from: action.value) ?? physicalKey, .focus)
        case .interruptAgent:
            guard confirmIfNeeded(action, forced: true) else { return }
            onAgentControl?(slot(from: action.value) ?? physicalKey, .interrupt)
        case .openURL:
            guard confirmIfNeeded(action), let url = URL(string: action.value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            NSWorkspace.shared.open(url)
        case .shellCommand:
            guard !action.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  confirmIfNeeded(action, forced: true) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", action.value]
            do { try process.run() } catch {
                presentError("Could not run workflow", detail: error.localizedDescription)
            }
        }
    }

    private func slot(from value: String) -> Int? {
        guard let slot = Int(value), (1...4).contains(slot) else { return nil }
        return slot
    }

    private func confirmIfNeeded(_ action: WorkflowAction, forced: Bool = false) -> Bool {
        guard forced || action.requiresConfirmation else { return true }
        let alert = NSAlert()
        alert.messageText = "Run \(action.label)?"
        alert.informativeText = action.value.isEmpty ? action.kind.displayName : action.value
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
