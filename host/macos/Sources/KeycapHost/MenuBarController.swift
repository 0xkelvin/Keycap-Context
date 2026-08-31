// SPDX-License-Identifier: Apache-2.0
import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject {
    var onPauseChanged: ((Bool) -> Void)?
    var onShowTestOverlay: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onShowAgentConsole: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let brokerItem = NSMenuItem(title: "Broker: starting", action: nil, keyEquivalent: "")
    private let deviceItem = NSMenuItem(title: "Device: disconnected", action: nil, keyEquivalent: "")
    private let queueItem = NSMenuItem(title: "Queue: empty", action: nil, keyEquivalent: "")
    private let firmwareItem = NSMenuItem(title: "Firmware: unknown", action: nil, keyEquivalent: "")
    private lazy var pauseItem = NSMenuItem(
        title: "Pause overlays", action: #selector(togglePause(_:)), keyEquivalent: "p"
    )
    private lazy var launchAtLoginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: ""
    )

    override init() {
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.and.hand.point.up.left",
            accessibilityDescription: "Keycap Context"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Keycap Context"

        let menu = NSMenu()
        menu.addItem(brokerItem)
        menu.addItem(deviceItem)
        menu.addItem(queueItem)
        menu.addItem(firmwareItem)
        menu.addItem(.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)

        let testItem = NSMenuItem(
            title: "Show Test Overlay", action: #selector(showTestOverlay(_:)), keyEquivalent: "t"
        )
        testItem.target = self
        menu.addItem(testItem)

        let consoleItem = NSMenuItem(
            title: "Agent Console…", action: #selector(showAgentConsole(_:)), keyEquivalent: "a"
        )
        consoleItem.target = self
        menu.addItem(consoleItem)

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let diagnosticsItem = NSMenuItem(
            title: "Export Diagnostics…", action: #selector(exportDiagnostics(_:)), keyEquivalent: ""
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        if !launchAtLoginItem.isEnabled {
            launchAtLoginItem.toolTip = "Launch at Login is available in the packaged app"
        }
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Keycap Context", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func update(_ status: HostStatus) {
        switch status.broker {
        case .starting:
            brokerItem.title = "Broker: starting"
        case .listening(let port):
            brokerItem.title = "Broker: 127.0.0.1:\(port)"
        case .failed(let message):
            brokerItem.title = "Broker error: \(message)"
        }

        switch status.device {
        case .disabled: deviceItem.title = "Device: disabled"
        case .disconnected: deviceItem.title = "Device: disconnected"
        case .connecting(let path): deviceItem.title = "Device: connecting \(path)"
        case .connected(let path): deviceItem.title = "Device: \((path as NSString).lastPathComponent)"
        case .failed(let message): deviceItem.title = "Device error: \(message)"
        }

        if status.queueCount == 0 {
            queueItem.title = "Queue: empty"
        } else if let agent = status.activeAgent {
            queueItem.title = "Queue: \(status.queueCount) · \(agent)"
        } else {
            queueItem.title = "Queue: \(status.queueCount)"
        }
        pauseItem.state = status.isPaused ? .on : .off

        let healthy: Bool
        if case .listening = status.broker { healthy = true } else { healthy = false }
        statusItem.button?.contentTintColor = status.isPaused ? .systemOrange : (healthy ? nil : .systemRed)
        statusItem.button?.toolTip = status.isPaused ? "Keycap Context paused" : "Keycap Context"
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        onPauseChanged?(sender.state != .on)
    }

    @objc private func showTestOverlay(_ sender: NSMenuItem) {
        onShowTestOverlay?()
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        onShowSettings?()
    }

    @objc private func showAgentConsole(_ sender: NSMenuItem) {
        onShowAgentConsole?()
    }

    @objc private func exportDiagnostics(_ sender: NSMenuItem) {
        onExportDiagnostics?()
    }

    func updateDeviceInfo(firmware: String?, protocolVersion: Int?) {
        if let firmware, let protocolVersion {
            firmwareItem.title = "Firmware: \(firmware) · protocol \(protocolVersion)"
        } else {
            firmwareItem.title = "Firmware: unknown"
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard sender.isEnabled else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateLaunchAtLoginState()
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
