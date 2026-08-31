// SPDX-License-Identifier: Apache-2.0
import Carbon.HIToolbox

@MainActor
protocol DismissShortcutMonitoring: AnyObject {
    func start(handler: @escaping @MainActor () -> Void) throws
    func stop()
}

enum DismissShortcutError: Error, Equatable {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)
}

struct HotKeyPressLatch {
    private(set) var isArmed = true

    mutating func press() -> Bool {
        guard isArmed else { return false }
        isArmed = false
        return true
    }

    mutating func release() {
        isArmed = true
    }
}

/// Owns the lifecycle of the shortcut separately from the overlay view.
///
/// Keeping this coordinator independent makes keyboard dismissal testable and
/// ensures the system-wide shortcut only exists while an overlay is visible.
@MainActor
final class DismissShortcutCoordinator {
    private let monitor: DismissShortcutMonitoring
    private let onDismiss: @MainActor () -> Void
    private var isEnabled = false

    init(
        monitor: DismissShortcutMonitoring,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.monitor = monitor
        self.onDismiss = onDismiss
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        if enabled {
            do {
                try monitor.start { [weak self] in
                    self?.onDismiss()
                }
                isEnabled = true
            } catch {
                // The button remains available if macOS reserves Escape or
                // registration otherwise fails.
                fputs("Could not register Escape dismissal shortcut: \(error)\n", stderr)
            }
        } else {
            monitor.stop()
            isEnabled = false
        }
    }
}

/// Registers bare Escape through the macOS hot-key API. Unlike a global event
/// monitor or event tap, this does not require Accessibility/Input Monitoring.
/// Registration is temporary and Escape is consumed only while an overlay is
/// active.
@MainActor
final class EscapeHotKeyMonitor: DismissShortcutMonitoring {
    private static let signature: OSType = 0x4B_43_50_45 // "KCPE"
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var handler: (@MainActor () -> Void)?
    private var pressLatch = HotKeyPressLatch()

    func start(handler: @escaping @MainActor () -> Void) throws {
        self.handler = handler
        guard hotKey == nil else { return }

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<EscapeHotKeyMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return monitor.receive(event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            self.handler = nil
            throw DismissShortcutError.eventHandlerRegistrationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            self.handler = nil
            throw DismissShortcutError.hotKeyRegistrationFailed(hotKeyStatus)
        }

        pressLatch.release()
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
        pressLatch.release()
    }

    private func receive(_ event: EventRef) -> OSStatus {
        var receivedID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )
        guard parameterStatus == noErr,
              receivedID.signature == Self.signature,
              receivedID.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard pressLatch.press() else { return noErr }
            handler?()
            return noErr
        case UInt32(kEventHotKeyReleased):
            pressLatch.release()
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
