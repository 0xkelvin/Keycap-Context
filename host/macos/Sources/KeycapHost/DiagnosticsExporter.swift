// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation

struct DiagnosticsReport: Codable {
    let generatedAt: Date
    let hostStatus: String
    let brokerPort: UInt16
    let queueCount: Int
    let paused: Bool
    let device: String
    let firmware: String?
    let protocolVersion: Int?
    let preferencesSchema: Int
}

@MainActor
enum DiagnosticsExporter {
    static func presentSavePanel(report: DiagnosticsReport) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "keycap-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
