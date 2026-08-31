// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation
import KeycapCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: HostConfiguration
    private let broker = RequestBroker()
    private let overlay: OverlayController
    private let menuBar = MenuBarController()
    private let preferences = PreferencesStore()
    private let agentConsoleStore = AgentConsoleStore()
    private let workflowExecutor = WorkflowExecutor()
    private lazy var settingsWindow = SettingsWindowController(store: preferences)
    private lazy var agentConsoleWindow = AgentConsoleWindowController(
        store: agentConsoleStore,
        onControl: { [weak self] key, action in self?.handleAgentControl(key: key, action: action) }
    )
    private let deviceController: DeviceConnectionController
    private var status = HostStatus()
    private var deviceProtocolVersion: Int?
    private var deviceFirmware: String?
    private var visibleChoiceCount = 0
    private var gesturesConsumedByImmediateChoice: Set<Int> = []
    private var idleFocusConsumedByButtonDown: Set<Int> = []
    private var preferenceSyncTask: Task<Void, Never>?
    private var server: LocalHTTPServer?

    init(configuration: HostConfiguration) {
        self.configuration = configuration
        self.overlay = OverlayController(position: configuration.overlayPosition)
        self.deviceController = DeviceConnectionController(
            preferredPath: configuration.serialPath,
            autodetect: configuration.autodetectSerial
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        overlay.onResolve = { [weak self] choiceIDs in
            guard let self, self.broker.resolve(choiceIDs: choiceIDs) != nil else { return }
            self.flashDeviceSuccess()
        }
        overlay.onDismiss = { [weak self] in
            _ = self?.broker.cancelActive()
        }
        broker.onChange = { [weak self] request, count in
            guard let self else { return }
            if let request {
                print("Keycap overlay \(request.id) choices=\(request.choices.count) visible=\(min(request.choices.count, 4))")
                fflush(stdout)
            }
            self.overlay.present(request, queueCount: count)
            self.status.queueCount = count
            self.status.activeAgent = request?.source
            self.updateStatus()
        }
        overlay.onVisibleChoiceCountChange = { [weak self] count in
            self?.visibleChoiceCount = count
            self?.updateDeviceStatus()
        }

        menuBar.onPauseChanged = { [weak self] paused in
            guard let self else { return }
            self.broker.setPaused(paused)
            self.status.isPaused = paused
            self.updateStatus()
            self.updateDeviceStatus()
        }
        menuBar.onShowTestOverlay = { [weak self] in self?.enqueueDemo() }
        menuBar.onShowSettings = { [weak self] in self?.settingsWindow.present() }
        menuBar.onShowAgentConsole = { [weak self] in self?.agentConsoleWindow.present() }
        menuBar.onExportDiagnostics = { [weak self] in self?.exportDiagnostics() }
        overlay.applyInteractionPreferences(preferences.preferences.interaction)
        preferences.onChange = { [weak self] preferences in
            self?.overlay.applyInteractionPreferences(preferences.interaction)
            self?.schedulePreferenceSync()
        }
        agentConsoleStore.onChange = { [weak self] in self?.updateDeviceStatus() }
        workflowExecutor.onAgentControl = { [weak self] key, action in
            self?.handleAgentControl(key: key, action: action)
        }

        deviceController.onEvent = { [weak self] event in self?.handleDeviceEvent(event) }
        deviceController.onStatusChange = { [weak self] deviceStatus in
            self?.status.device = deviceStatus
            if case .connected = deviceStatus {
                // Wait for HELLO before choosing protocol v1 or v2.
            } else {
                self?.gesturesConsumedByImmediateChoice.removeAll()
                self?.idleFocusConsumedByButtonDown.removeAll()
                self?.deviceProtocolVersion = nil
                self?.deviceFirmware = nil
                self?.menuBar.updateDeviceInfo(firmware: nil, protocolVersion: nil)
            }
            self?.updateStatus()
        }

        do {
            let (token, tokenURL) = try BrokerToken.loadOrCreate()
            print("Keycap broker token: \(tokenURL.path)")
            fflush(stdout)
            let server = try LocalHTTPServer(
                port: configuration.port,
                token: token,
                broker: broker,
                agentConsole: agentConsoleStore.console,
                healthProvider: { [weak self, port = configuration.port] in
                    self?.healthSnapshot() ?? HealthSnapshot(
                        status: "starting", port: port, paused: false,
                        queueCount: 0, activeAgent: nil, device: "disconnected"
                    )
                }
            )
            server.onStateChange = { [weak self] state in
                switch state {
                case .starting: self?.status.broker = .starting
                case .ready(let port): self?.status.broker = .listening(port)
                case .failed(let error): self?.status.broker = .failed(error)
                }
                self?.updateStatus()
            }
            server.start()
            self.server = server
        } catch {
            fputs("Could not start local broker: \(error)\n", stderr)
            NSApplication.shared.terminate(nil)
            return
        }

        deviceController.start()
        updateStatus()

        if CommandLine.arguments.contains("--demo") {
            enqueueDemo()
        }
        if preferences.isFirstLaunch {
            settingsWindow.present()
        }
    }

    private func handleDeviceEvent(_ event: DeviceEvent) {
        switch event {
        case .button(let key, let isDown, let sequence):
            let state = isDown ? "down" : "up"
            print("Keycap button \(key) \(state) #\(sequence)")
            fflush(stdout)
            if isDown && overlay.isPresentingRequest &&
               ((deviceProtocolVersion ?? 1) == 1 || overlay.acceptsImmediateHardwareChoice) {
                if (deviceProtocolVersion ?? 1) >= 2 {
                    gesturesConsumedByImmediateChoice.insert(key)
                }
                overlay.handleHardwareChoice(key)
            } else if isDown && !overlay.isPresentingRequest &&
                      agentConsoleStore.console.session(forKey: key) != nil {
                // Focusing must feel like a hardware switch, not a click
                // gesture. Waiting for SHORT adds the double-press window and
                // makes an impatient retry become MARK READ instead.
                idleFocusConsumedByButtonDown.insert(key)
                handleAgentControl(key: key, action: .focus)
            }
        case .gesture(let key, let kind, let sequence):
            print("Keycap gesture \(key) \(kind.rawValue.lowercased()) #\(sequence)")
            fflush(stdout)
            if gesturesConsumedByImmediateChoice.remove(key) != nil {
                return
            }
            if idleFocusConsumedByButtonDown.remove(key) != nil, kind == .short {
                return
            }
            if overlay.isPresentingRequest {
                overlay.handleHardwareGesture(key: key, kind: kind)
            } else {
                handleIdleGesture(key: key, kind: kind)
            }
        case .hello(let version, _, _) where !(1...3).contains(version):
            fputs("Unsupported device protocol version \(version)\n", stderr)
        case .hello(let version, let firmware, _):
            gesturesConsumedByImmediateChoice.removeAll()
            idleFocusConsumedByButtonDown.removeAll()
            deviceProtocolVersion = version
            deviceFirmware = firmware
            menuBar.updateDeviceInfo(firmware: firmware, protocolVersion: version)
            updateDeviceStatus()
            sendLightingProfile()
        case .error(let code):
            fputs("Device error: \(code)\n", stderr)
        }
    }

    private func updateDeviceStatus() {
        guard let version = deviceProtocolVersion else { return }
        if version >= 2 {
            let deviceState: DeviceProtocolV2.Status
            if broker.isPaused {
                deviceState = .paused
            } else if visibleChoiceCount > 0 {
                deviceState = .waiting(
                    activeChoices: visibleChoiceCount,
                    colorHex: broker.active?.accentColor
                )
            } else if version >= 3 && preferences.preferences.showAgentActivityOnKeys {
                deviceController.write(DeviceProtocolV2.status(.idle))
                deviceController.write(DeviceProtocolV3.agents(agentLEDStates()))
                return
            } else {
                deviceState = .idle
            }
            deviceController.write(DeviceProtocolV2.status(deviceState))
        } else {
            deviceController.write(DeviceProtocolV1.leds(activeChoices: visibleChoiceCount))
        }
    }

    private func agentLEDStates() -> [AgentLEDState] {
        agentConsoleStore.console.slots.map { session in
            guard let session else { return .empty }
            if session.destructiveApproval { return .destructive }
            switch session.state {
            case .idle: return .idle
            case .working: return .working
            case .waiting: return .waiting
            case .completed: return .completed
            case .failed: return .failed
            }
        }
    }

    private func handleIdleGesture(key: Int, kind: GestureKind) {
        if agentConsoleStore.console.session(forKey: key) != nil {
            switch kind {
            case .short: handleAgentControl(key: key, action: .focus)
            case .long: handleAgentControl(key: key, action: .interrupt)
            case .double: handleAgentControl(key: key, action: .markRead)
            }
            return
        }
        guard kind == .short, preferences.preferences.contextAwareProfilesEnabled,
              let profile = ContextProfileMatcher.match(
                preferences.preferences.contextProfiles,
                applicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                project: nil
              ), profile.actions.indices.contains(key - 1) else { return }
        workflowExecutor.execute(profile.actions[key - 1], physicalKey: key)
    }

    private func handleAgentControl(key: Int, action: AgentControlAction) {
        guard let session = agentConsoleStore.console.session(forKey: key) else { return }
        if action == .unassign {
            _ = agentConsoleStore.console.remove(session: session.session)
            return
        }
        if action == .interrupt || action == .cancel {
            _ = broker.cancel(session: session.session, reason: "hardware-interrupt")
        }
        _ = agentConsoleStore.console.enqueueControl(key: key, action: action)
        if action == .focus {
            focus(session)
        } else if action == .resume {
            _ = agentConsoleStore.console.update(AgentStatusUpdate(
                session: session.session, source: session.source,
                project: session.project, context: session.context,
                state: .working, summary: "Resume requested",
                clientApp: session.clientApp, preferredKey: key
            ))
        }
    }

    private func focus(_ session: AgentSession) {
        guard let bundleIdentifier = session.clientApp, !bundleIdentifier.isEmpty,
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
              ).first else {
            agentConsoleWindow.present()
            return
        }
        // Activating the app leaves its windows on their existing displays and
        // lets macOS raise the most recently used terminal window. Raising all
        // windows is disruptive on multi-monitor desktops.
        application.activate(options: [])
    }

    private func flashDeviceSuccess() {
        guard (deviceProtocolVersion ?? 0) >= 2 else { return }
        deviceController.write(DeviceProtocolV2.status(.success))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.updateDeviceStatus()
        }
    }

    private func sendLightingProfile() {
        guard (deviceProtocolVersion ?? 0) >= 2 else { return }
        deviceController.write(DeviceProtocolV2.lighting(preferences.preferences.lighting))
    }

    private func schedulePreferenceSync() {
        preferenceSyncTask?.cancel()
        preferenceSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 75_000_000)
            guard !Task.isCancelled, let self else { return }
            self.sendLightingProfile()
            self.updateDeviceStatus()
        }
    }

    private func updateStatus() {
        menuBar.update(status)
    }

    private func healthSnapshot() -> HealthSnapshot {
        let brokerValue: String
        switch status.broker {
        case .starting: brokerValue = "starting"
        case .listening: brokerValue = "ok"
        case .failed: brokerValue = "error"
        }
        return HealthSnapshot(
            status: brokerValue,
            port: configuration.port,
            paused: broker.isPaused,
            queueCount: broker.count,
            activeAgent: broker.active?.source,
            device: status.device.healthValue
        )
    }

    private func exportDiagnostics() {
        let snapshot = healthSnapshot()
        DiagnosticsExporter.presentSavePanel(report: DiagnosticsReport(
            generatedAt: Date(), hostStatus: snapshot.status, brokerPort: snapshot.port,
            queueCount: snapshot.queueCount, paused: snapshot.paused,
            device: snapshot.device, firmware: deviceFirmware,
            protocolVersion: deviceProtocolVersion,
            preferencesSchema: preferences.preferences.schemaVersion
        ))
    }

    private func enqueueDemo() {
        let request = AgentRequest(
            id: "demo-\(UUID().uuidString)",
            source: "Claude",
            session: "demo-session",
            project: "Keycap Context",
            context: "Zellij pane 1",
            kind: "question",
            title: "How should the first adapter expose agent choices?",
            detail: "The displayed text and ordering are preserved exactly as submitted.",
            choices: [
                Choice(id: "native", label: "Native protocol",
                       description: "Use structured lifecycle events from the agent."),
                Choice(id: "hook", label: "Lifecycle hook",
                       description: "Wait for the physical selection in a local hook."),
                Choice(id: "pty", label: "Managed terminal",
                       description: "Parse a CLI only when no structured interface exists."),
                Choice(id: "later", label: "Decide later",
                       description: "Keep the request queued without changing the terminal."),
            ]
        )
        _ = broker.submit(request) { resolution in
            switch resolution {
            case .selected(let response):
                print("Demo selected option \(response.choiceIndex + 1): \(response.choiceId)")
            case .cancelled:
                print("Demo handed back to the agent")
            }
        }
    }
}

MainActor.assumeIsolated {
    do {
        // The LaunchAgent redirects stdout to a file, which makes it block
        // buffered: diagnostic lines about reconnects would sit unseen for
        // kilobytes. Line buffering keeps the log usable while it is happening.
        setvbuf(stdout, nil, _IOLBF, 0)
        let configuration = try HostConfiguration.parse()
        let application = NSApplication.shared
        let delegate = AppDelegate(configuration: configuration)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    } catch {
        fputs("Invalid Keycap configuration: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
