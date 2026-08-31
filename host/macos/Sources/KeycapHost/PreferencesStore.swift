// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation
import KeycapCore

struct InteractionPreferences: Codable, Equatable {
    var holdToConfirmDestructive = true
    var showQueueCount = true
    var shortPressAction = "select"
    var longPressAction = "contextual"
    var doublePressAction = "navigate"
}

struct AppPreferences: Codable, Equatable {
    var schemaVersion = 3
    var lighting = LightingProfile()
    var showAgentActivityOnKeys = false
    var interaction = InteractionPreferences()
    var contextAwareProfilesEnabled = true
    var contextProfiles: [ContextProfile] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, lighting, showAgentActivityOnKeys, interaction
        case contextAwareProfilesEnabled, contextProfiles
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        lighting = try values.decodeIfPresent(LightingProfile.self, forKey: .lighting)
            ?? LightingProfile()
        showAgentActivityOnKeys = try values.decodeIfPresent(
            Bool.self, forKey: .showAgentActivityOnKeys
        ) ?? false
        interaction = try values.decodeIfPresent(
            InteractionPreferences.self, forKey: .interaction
        ) ?? InteractionPreferences()
        contextAwareProfilesEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .contextAwareProfilesEnabled
        ) ?? true
        contextProfiles = try values.decodeIfPresent(
            [ContextProfile].self, forKey: .contextProfiles
        ) ?? []
        schemaVersion = 3
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet {
            save()
            onChange?(preferences)
        }
    }

    var onChange: ((AppPreferences) -> Void)?
    let fileURL: URL
    let isFirstLaunch: Bool

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.isFirstLaunch = !FileManager.default.fileExists(atPath: self.fileURL.path)
        self.preferences = Self.load(from: self.fileURL) ?? AppPreferences()
        if isFirstLaunch { save() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("previous")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            try encoder.encode(preferences).write(to: fileURL, options: .atomic)
        } catch {
            fputs("Could not save Keycap preferences: \(error)\n", stderr)
        }
    }

    private static func load(from url: URL) -> AppPreferences? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppPreferences.self, from: data)
    }

    private static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["KEYCAP_SETTINGS_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent("Keycap Context/settings.json")
    }
}
