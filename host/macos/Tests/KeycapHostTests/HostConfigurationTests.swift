// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import KeycapHost

final class HostConfigurationTests: XCTestCase {
    func testDefaults() throws {
        let configuration = try HostConfiguration.parse(
            arguments: ["keycap-host"], environment: [:]
        )

        XCTAssertEqual(configuration.port, 47_821)
        XCTAssertTrue(configuration.autodetectSerial)
        XCTAssertEqual(configuration.overlayPosition, .topCenter)
    }

    func testArgumentsOverrideEnvironment() throws {
        let configuration = try HostConfiguration.parse(
            arguments: [
                "keycap-host", "--port", "49000", "--serial", "/dev/test",
                "--overlay-position", "top-right",
            ],
            environment: [
                "KEYCAP_PORT": "48000",
                "KEYCAP_OVERLAY_POSITION": "top-left",
            ]
        )

        XCTAssertEqual(configuration.port, 49_000)
        XCTAssertEqual(configuration.serialPath, "/dev/test")
        XCTAssertFalse(configuration.autodetectSerial)
        XCTAssertEqual(configuration.overlayPosition, .topRight)
    }

    func testNoSerialDisablesDiscovery() throws {
        let configuration = try HostConfiguration.parse(
            arguments: ["keycap-host", "--no-serial"],
            environment: ["KEYCAP_SERIAL_PATH": "/dev/environment"]
        )

        XCTAssertNil(configuration.serialPath)
        XCTAssertFalse(configuration.autodetectSerial)
    }

    func testRejectsInvalidPort() {
        XCTAssertThrowsError(try HostConfiguration.parse(
            arguments: ["keycap-host", "--port", "70000"], environment: [:]
        ))
    }
}
