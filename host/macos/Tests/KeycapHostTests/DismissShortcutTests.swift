// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import KeycapHost

@MainActor
final class DismissShortcutTests: XCTestCase {
    func testShortcutDismissesVisibleOverlay() {
        let monitor = FakeDismissShortcutMonitor()
        var dismissCount = 0
        let coordinator = DismissShortcutCoordinator(monitor: monitor) {
            dismissCount += 1
        }

        coordinator.setEnabled(true)
        monitor.trigger()

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(monitor.startCount, 1)
    }

    func testShortcutIsRemovedWhenOverlayDisappears() {
        let monitor = FakeDismissShortcutMonitor()
        var dismissCount = 0
        let coordinator = DismissShortcutCoordinator(monitor: monitor) {
            dismissCount += 1
        }

        coordinator.setEnabled(true)
        coordinator.setEnabled(false)
        monitor.trigger()

        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testRepeatedPresentationDoesNotRegisterDuplicateShortcut() {
        let monitor = FakeDismissShortcutMonitor()
        let coordinator = DismissShortcutCoordinator(monitor: monitor) {}

        coordinator.setEnabled(true)
        coordinator.setEnabled(true)

        XCTAssertEqual(monitor.startCount, 1)
    }

    func testHeldEscapeProducesOnlyOneDismissal() {
        var latch = HotKeyPressLatch()

        XCTAssertTrue(latch.press())
        XCTAssertFalse(latch.press())
        XCTAssertFalse(latch.press())
    }

    func testEscapeRearmsAfterKeyRelease() {
        var latch = HotKeyPressLatch()

        XCTAssertTrue(latch.press())
        latch.release()

        XCTAssertTrue(latch.press())
    }
}

@MainActor
private final class FakeDismissShortcutMonitor: DismissShortcutMonitoring {
    private var handler: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @MainActor () -> Void) throws {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func trigger() {
        handler?()
    }
}
