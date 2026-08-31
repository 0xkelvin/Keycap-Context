// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import KeycapHost
import KeycapCore

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testPreferencesPersistAndRetainPreviousVersion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keycap-preferences-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PreferencesStore(fileURL: file)
        XCTAssertTrue(store.isFirstLaunch)
        store.preferences.lighting.mode = .breathing
        store.preferences.lighting.brightness = 42
        store.preferences.showAgentActivityOnKeys = true

        let restored = PreferencesStore(fileURL: file)
        XCTAssertFalse(restored.isFirstLaunch)
        XCTAssertEqual(restored.preferences.lighting.mode, .breathing)
        XCTAssertEqual(restored.preferences.lighting.brightness, 42)
        XCTAssertTrue(restored.preferences.showAgentActivityOnKeys)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: file.appendingPathExtension("previous").path
        ))
    }

    func testExistingPreferencesDefaultToStandbyLighting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keycap-preferences-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2,"lighting":{"mode":"wave","brightness":70,"speed":50,"keyColors":["00FF20","0070FF","DC00FF","FF4800"]}}"#.utf8)
            .write(to: file)

        let restored = PreferencesStore(fileURL: file)

        XCTAssertEqual(restored.preferences.schemaVersion, 3)
        XCTAssertEqual(restored.preferences.lighting.mode, .wave)
        XCTAssertFalse(restored.preferences.showAgentActivityOnKeys)
    }
}
