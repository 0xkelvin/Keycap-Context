// SPDX-License-Identifier: Apache-2.0
import AppKit
import KeycapCore
import SwiftUI

@MainActor
final class AgentConsoleWindowController: NSWindowController {
    init(
        store: AgentConsoleStore,
        onControl: @escaping (Int, AgentControlAction) -> Void
    ) {
        let controller = NSHostingController(rootView: AgentConsoleView(
            store: store, onControl: onControl
        ))
        let window = NSWindow(contentViewController: controller)
        window.title = "Keycap Agent Console"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 620))
        window.minSize = NSSize(width: 620, height: 440)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct AgentConsoleView: View {
    @ObservedObject var store: AgentConsoleStore
    let onControl: (Int, AgentControlAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Four-agent control surface")
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                ForEach(1...4, id: \.self) { key in
                    agentCard(key: key, session: store.sessions.first { $0.assignedKey == key })
                }
            }
            Divider()
            Text("Approval and control history")
                .font(.headline)
            List(store.history) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(event.risk == .destructive ? Color.pink : Color.secondary)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.source) · \(event.kind.rawValue)")
                            .font(.caption.weight(.semibold))
                        Text(event.summary).lineLimit(2)
                    }
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .padding(20)
    }

    @ViewBuilder
    private func agentCard(key: Int, session: AgentSession?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("KEY \(key)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(statusColor(session)).frame(width: 10, height: 10)
            }
            Text(session?.source ?? "Unassigned").font(.headline).lineLimit(1)
            Text(session?.project ?? session?.summary ?? "Waiting for an agent")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(session?.state.rawValue.uppercased() ?? "EMPTY")
                .font(.caption2.monospaced().bold())
            HStack(spacing: 5) {
                Button("Focus") { onControl(key, .focus) }.disabled(session == nil)
                Button("Stop") { onControl(key, .interrupt) }.disabled(session == nil)
            }
            .controlSize(.small)
            HStack(spacing: 5) {
                Button("Resume") { onControl(key, .resume) }.disabled(session == nil)
                Button("Cancel") { onControl(key, .cancel) }.disabled(session == nil)
                Button("Unassign") { onControl(key, .unassign) }.disabled(session == nil)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusColor(_ session: AgentSession?) -> Color {
        guard let session else { return .gray.opacity(0.35) }
        if session.destructiveApproval { return .pink }
        switch session.state {
        case .idle: return .blue.opacity(0.45)
        case .working: return .blue
        case .waiting: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}
