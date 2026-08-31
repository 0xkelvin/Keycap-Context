// SPDX-License-Identifier: Apache-2.0
import AppKit
import CoreGraphics
import KeycapCore

@MainActor
final class OverlayController: NSObject {
    var onResolve: (([String]) -> Void)?
    var onDismiss: (() -> Void)?
    var onVisibleChoiceCountChange: ((Int) -> Void)?
    var requiresHoldToConfirmDestructive = true
    var gestureActions: [GestureKind: String] = [
        .short: "select", .long: "contextual", .double: "navigate",
    ]

    private let panel: NSPanel
    private let preferredPosition: OverlayPosition
    private let glassView = GlassContainerView()
    private let contentStack = NSStackView()
    private var dismissShortcut: DismissShortcutCoordinator!
    private var interaction: RequestInteraction?
    private var queueCount = 0
    private var deadline: Date?
    private var timeoutTimer: Timer?
    private weak var stateLabel: NSTextField?
    var isPresentingRequest: Bool { interaction != nil }
    var acceptsImmediateHardwareChoice: Bool {
        interaction?.acceptsImmediateSelection == true
    }

    override convenience init() {
        self.init(position: .topCenter, dismissShortcutMonitor: EscapeHotKeyMonitor())
    }

    convenience init(position: OverlayPosition) {
        self.init(position: position, dismissShortcutMonitor: EscapeHotKeyMonitor())
    }

    init(position: OverlayPosition, dismissShortcutMonitor: DismissShortcutMonitoring) {
        preferredPosition = position
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        dismissShortcut = DismissShortcutCoordinator(
            monitor: dismissShortcutMonitor,
            onDismiss: { [weak self] in self?.onDismiss?() }
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.contentView = glassView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        glassView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 22),
            contentStack.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -22),
            contentStack.topAnchor.constraint(equalTo: glassView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: glassView.bottomAnchor, constant: -20),
        ])
    }

    func present(_ request: AgentRequest?, queueCount: Int) {
        self.queueCount = queueCount
        guard let request else {
            interaction = nil
            deadline = nil
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            dismissShortcut.setEnabled(false)
            panel.orderOut(nil)
            onVisibleChoiceCountChange?(0)
            return
        }

        if interaction?.request.id != request.id {
            interaction = RequestInteraction(
                request: request,
                requiresConfirmation: requiresHoldToConfirmDestructive && request.risk == .destructive
            )
            deadline = request.timeoutSeconds.map { Date().addingTimeInterval($0) }
            startTimeoutTimerIfNeeded()
        }
        render()
    }

    func handleHardwareChoice(_ number: Int) {
        handle(interactionChange: { $0.selectVisibleChoice(number: number) })
    }

    func handleHardwareGesture(key: Int, kind: GestureKind) {
        let action = gestureActions[kind] ?? "none"
        switch action {
        case "select":
            handleHardwareChoice(key)
        case "navigate":
            if key == 1 { showPreviousPage() }
            if key == 4 { showNextPage() }
        case "dismiss":
            onDismiss?()
        case "contextual":
            if interaction?.requiresConfirmation == true {
                handle(interactionChange: { $0.confirmVisibleChoice(number: key) })
                return
            }
            switch key {
            case 1: showPreviousPage()
            case 2: clearSelection()
            case 3: onDismiss?()
            case 4:
                if interaction?.allowsMultiple == true {
                    submitSelection()
                } else {
                    showNextPage()
                }
            default: break
            }
        default:
            break
        }
    }

    func applyInteractionPreferences(_ preferences: InteractionPreferences) {
        requiresHoldToConfirmDestructive = preferences.holdToConfirmDestructive
        gestureActions = [
            .short: preferences.shortPressAction,
            .long: preferences.longPressAction,
            .double: preferences.doublePressAction,
        ]
    }

    func showPreviousPage() {
        handle(interactionChange: { $0.goToPreviousPage() })
    }

    func showNextPage() {
        handle(interactionChange: { $0.goToNextPage() })
    }

    func clearSelection() {
        handle(interactionChange: { $0.clearSelection() })
    }

    func submitSelection() {
        guard let interaction else { return }
        apply(interaction.submit())
    }

    private func render() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let interaction else { return }
        let request = interaction.request

        dismissShortcut.setEnabled(true)

        let header = makeHeader(for: request, queueCount: queueCount)
        contentStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        let title = wrappingLabel(
            request.title,
            font: .systemFont(ofSize: 20, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 3
        contentStack.addArrangedSubview(title)
        title.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        if let detail = request.detail, !detail.isEmpty {
            let detailLabel = wrappingLabel(
                detail,
                font: .monospacedSystemFont(ofSize: 12.5, weight: .regular),
                color: .secondaryLabelColor
            )
            detailLabel.maximumNumberOfLines = 6
            contentStack.addArrangedSubview(detailLabel)
            detailLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let choices = NSStackView()
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 8
        for (index, choice) in interaction.visibleChoices.enumerated() {
            let button = ChoiceButton(
                number: index + 1,
                choice: choice,
                selected: interaction.selectedChoiceIDs.contains(choice.id)
                    || interaction.pendingConfirmationChoiceID == choice.id
            )
            button.tag = index + 1
            button.target = self
            button.action = #selector(choicePressed(_:))
            choices.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: choices.widthAnchor).isActive = true
        }
        contentStack.addArrangedSubview(choices)
        choices.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        if !interaction.controls.isEmpty {
            let controls = makeInteractionControls(interaction)
            contentStack.addArrangedSubview(controls)
            controls.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = contentStack.fittingSize
        let height = min(max(fitting.height + 38, 220), 780)
        panel.setContentSize(NSSize(width: 640, height: height))
        positionOnWorkingScreen()
        panel.orderFrontRegardless()
        onVisibleChoiceCountChange?(interaction.visibleChoices.count)
    }

    @objc private func choicePressed(_ sender: NSButton) {
        handleHardwareChoice(sender.tag)
    }

    @objc private func dismissPressed(_ sender: NSButton) {
        onDismiss?()
    }

    @objc private func previousPressed(_ sender: NSButton) { showPreviousPage() }
    @objc private func nextPressed(_ sender: NSButton) { showNextPage() }
    @objc private func clearPressed(_ sender: NSButton) { clearSelection() }
    @objc private func submitPressed(_ sender: NSButton) { submitSelection() }

    private func handle(
        interactionChange: (inout RequestInteraction) -> InteractionOutcome
    ) {
        guard var interaction else { return }
        let outcome = interactionChange(&interaction)
        self.interaction = interaction
        apply(outcome)
    }

    private func apply(_ outcome: InteractionOutcome) {
        switch outcome {
        case .unchanged:
            break
        case .updated:
            render()
        case .resolved(let choiceIDs):
            onResolve?(choiceIDs)
        }
    }

    private func makeInteractionControls(_ interaction: RequestInteraction) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        var insertedSpacer = false
        for control in interaction.controls {
            if !control.isPagination && !insertedSpacer {
                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                row.addArrangedSubview(spacer)
                insertedSpacer = true
            }
            row.addArrangedSubview(controlButton(
                control.title,
                enabled: control.isEnabled,
                action: selector(for: control),
                emphasized: control.isEmphasized
            ))
        }
        if !insertedSpacer {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
        }
        return row
    }

    private func selector(for control: InteractionControl) -> Selector {
        switch control {
        case .previousPage: return #selector(previousPressed(_:))
        case .nextPage: return #selector(nextPressed(_:))
        case .clearSelection: return #selector(clearPressed(_:))
        case .submitSelection, .confirmSelection: return #selector(submitPressed(_:))
        }
    }

    private func controlButton(
        _ title: String,
        enabled: Bool,
        action: Selector,
        emphasized: Bool = false
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = emphasized ? .rounded : .inline
        button.isEnabled = enabled
        button.controlSize = .small
        return button
    }

    private func makeHeader(for request: AgentRequest, queueCount: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let statusDot = NSView()
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor(
            keycapHex: request.accentColor ?? "34C759"
        )?.cgColor ?? NSColor.systemGreen.cgColor
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        row.addArrangedSubview(statusDot)

        row.addArrangedSubview(pillLabel(request.source.uppercased()))

        let location = [request.project, request.context]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
        if !location.isEmpty {
            let label = NSTextField(labelWithString: location)
            label.font = .systemFont(ofSize: 11.5, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            row.addArrangedSubview(label)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let stateLabel = NSTextField(labelWithString: stateText())
        stateLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        stateLabel.textColor = .tertiaryLabelColor
        row.addArrangedSubview(stateLabel)
        self.stateLabel = stateLabel

        let agentName = request.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = agentName.isEmpty ? "agent" : agentName
        let dismiss = NSButton(
            title: "Handle in \(destination)",
            target: self,
            action: #selector(dismissPressed(_:))
        )
        dismiss.bezelStyle = .rounded
        dismiss.controlSize = .small
        dismiss.font = .systemFont(ofSize: 11.5, weight: .medium)
        dismiss.toolTip = "Dismiss this request and return it to \(destination)'s terminal (Escape)"
        dismiss.setAccessibilityLabel("Handle this request in \(destination)")
        row.addArrangedSubview(dismiss)
        return row
    }

    private func stateText() -> String {
        guard let interaction else { return "WAITING" }
        var parts: [String] = []
        if let progress = interaction.request.progress {
            parts.append("QUESTION \(progress.current) OF \(progress.total)")
        }
        if interaction.pageCount > 1 {
            parts.append("PAGE \(interaction.pageIndex + 1) OF \(interaction.pageCount)")
        }
        if interaction.allowsMultiple && !interaction.selectedChoiceIDs.isEmpty {
            parts.append("\(interaction.selectedChoiceIDs.count) SELECTED")
        }
        parts.append(contentsOf: interaction.gestureHints(
            longPress: gestureActions[.long] ?? "none",
            doublePress: gestureActions[.double] ?? "none"
        ))
        if let deadline {
            let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            parts.append("\(remaining)S")
        }
        if queueCount > 1 { parts.append("1 OF \(queueCount) QUEUED") }
        parts.append("WAITING")
        return parts.joined(separator: "  ·  ")
    }

    private func startTimeoutTimerIfNeeded() {
        timeoutTimer?.invalidate()
        guard deadline != nil else {
            timeoutTimer = nil
            return
        }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.stateLabel?.stringValue = self?.stateText() ?? "WAITING" }
        }
    }

    private func pillLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: "  \(text)  ")
        label.font = .systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        label.layer?.cornerRadius = 7
        label.layer?.cornerCurve = .continuous
        return label
    }

    private func wrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 8
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func positionOnWorkingScreen() {
        let screen = screenForFrontmostWindow() ?? screenUnderPointer() ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = panel.frame
        let x: CGFloat
        switch preferredPosition {
        case .topLeft: x = visible.minX + 28
        case .topCenter: x = visible.midX - frame.width / 2
        case .topRight: x = visible.maxX - frame.width - 28
        }
        panel.setFrameOrigin(NSPoint(
            x: x,
            y: visible.maxY - frame.height - 28
        ))
    }

    private func screenUnderPointer() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    private func screenForFrontmostWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]],
              let mainFrame = NSScreen.screens.first?.frame else { return nil }

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let quartzRect = CGRect(dictionaryRepresentation: bounds),
                  quartzRect.width > 80, quartzRect.height > 80 else { continue }
            let appKitRect = CGRect(
                x: quartzRect.minX,
                y: mainFrame.maxY - quartzRect.maxY,
                width: quartzRect.width,
                height: quartzRect.height
            )
            return NSScreen.screens.max {
                $0.frame.intersection(appKitRect).area < $1.frame.intersection(appKitRect).area
            }
        }
        return nil
    }
}

private final class GlassContainerView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Popover material follows the current light/dark appearance while
        // behind-window blending borrows ambient color from the focused app.
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
    }
}

private final class ChoiceButton: NSButton {
    private var hovering = false
    private let isSelectedChoice: Bool

    init(number: Int, choice: Choice, selected: Bool) {
        isSelectedChoice = selected
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        numberLabel.textColor = .secondaryLabelColor
        numberLabel.alignment = .center
        numberLabel.wantsLayer = true
        numberLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        numberLabel.layer?.cornerRadius = 8
        numberLabel.layer?.cornerCurve = .continuous
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            numberLabel.heightAnchor.constraint(equalToConstant: 28),
        ])

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(wrappingLabelWithString: choice.label)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 2
        textStack.addArrangedSubview(titleLabel)

        if let description = choice.description, !description.isEmpty {
            let descriptionLabel = NSTextField(wrappingLabelWithString: description)
            descriptionLabel.font = .systemFont(ofSize: 12, weight: .regular)
            descriptionLabel.textColor = .secondaryLabelColor
            descriptionLabel.maximumNumberOfLines = 3
            textStack.addArrangedSubview(descriptionLabel)
        }

        let arrow = NSTextField(labelWithString: selected ? "✓" : "›")
        arrow.font = .systemFont(ofSize: 22, weight: .regular)
        arrow.textColor = .tertiaryLabelColor

        let row = NSStackView(views: [numberLabel, textStack, arrow])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])

        toolTip = choice.description ?? choice.label
        setAccessibilityLabel("Option \(number): \(choice.label)")
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateAppearance(animated: true)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateAppearance(animated: true, pressed: flag)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance(animated: Bool = false, pressed: Bool = false) {
        let fill: NSColor
        let border: NSColor
        if pressed {
            fill = .controlAccentColor.withAlphaComponent(0.20)
            border = .controlAccentColor.withAlphaComponent(0.45)
        } else if isSelectedChoice {
            fill = .controlAccentColor.withAlphaComponent(0.18)
            border = .controlAccentColor.withAlphaComponent(0.48)
        } else if hovering {
            fill = .controlAccentColor.withAlphaComponent(0.13)
            border = .controlAccentColor.withAlphaComponent(0.32)
        } else {
            fill = .labelColor.withAlphaComponent(0.055)
            border = .labelColor.withAlphaComponent(0.11)
        }

        let changes = {
            self.layer?.backgroundColor = fill.cgColor
            self.layer?.borderColor = border.cgColor
        }
        layer?.borderWidth = 0.75
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                changes()
            }
        } else {
            changes()
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private extension NSColor {
    convenience init?(keycapHex: String) {
        guard keycapHex.count == 6, let value = Int(keycapHex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
