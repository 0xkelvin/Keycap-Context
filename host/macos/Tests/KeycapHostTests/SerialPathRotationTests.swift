// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import KeycapHost

final class SerialPathRotationTests: XCTestCase {
    func testHeartbeatProbesBeforeDisconnectingAfterSleepGap() {
        var recovery = HeartbeatRecovery()

        XCTAssertEqual(recovery.evaluate(timedOut: false), .normal)
        XCTAssertEqual(recovery.evaluate(timedOut: true), .probe)
        XCTAssertEqual(recovery.evaluate(timedOut: true), .disconnect)

        recovery.acknowledge()
        XCTAssertEqual(recovery.evaluate(timedOut: true), .probe)
        recovery.reset()
        XCTAssertEqual(recovery.evaluate(timedOut: true), .probe)
    }

    func testRotatesSortedUniqueCandidatesAfterFailure() {
        var rotation = SerialPathRotation()
        let candidates = ["/dev/cu.usbmodemB", "/dev/cu.usbmodemA", "/dev/cu.usbmodemA"]

        XCTAssertEqual(rotation.select(from: candidates), "/dev/cu.usbmodemA")
        rotation.advance()
        XCTAssertEqual(rotation.select(from: candidates), "/dev/cu.usbmodemB")
        rotation.advance()
        XCTAssertEqual(rotation.select(from: candidates), "/dev/cu.usbmodemA")
    }

    func testEmptyCandidateListIsSafe() {
        var rotation = SerialPathRotation()
        XCTAssertNil(rotation.select(from: []))
        rotation.advance()
        XCTAssertNil(rotation.select(from: []))
    }

    func testRememberedKeycapWinsOverMonitorControlModem() {
        var rotation = SerialPathRotation()
        let keycap = "/dev/cu.usbmodemSeeed"
        let monitor = "/dev/cu.usbmodemLG"

        rotation.rememberKeycap(keycap)
        rotation.advance()
        XCTAssertEqual(rotation.select(from: [monitor, keycap]), keycap)
        XCTAssertTrue(rotation.isRemembered(keycap))
        XCTAssertFalse(rotation.isRemembered(monitor))

        // If the board is physically unplugged, another candidate remains
        // discoverable rather than returning a stale path.
        XCTAssertEqual(rotation.select(from: [monitor]), monitor)
    }
}
