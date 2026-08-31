// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum LightingMode: String, Codable, CaseIterable, Sendable {
    case rainbow
    case wave
    case breathing
    case reactive
    case audio
    case spectrum
    case pitch
    case staticColor = "static"
    case off

    /// Decode leniently so one unrecognised effect cannot discard the whole
    /// preferences file. A strict decoder throws, `AppPreferences` decoding
    /// fails with it, and every unrelated setting silently reverts to its
    /// default -- which is what a downgrade to a host without this effect would
    /// otherwise do.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LightingMode(rawValue: raw) ?? .rainbow
    }

    public var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .wave: return "Color Wave"
        case .breathing: return "Breathing"
        case .reactive: return "Reactive"
        case .audio: return "Audio Meter"
        case .spectrum: return "Audio Spectrum"
        case .pitch: return "Pitch Colour"
        case .staticColor: return "Static"
        case .off: return "Off"
        }
    }
}

public struct LightingProfile: Codable, Equatable, Sendable {
    public var mode: LightingMode
    public var brightness: Int
    public var speed: Int
    public var keyColors: [String]

    public init(
        mode: LightingMode = .rainbow,
        brightness: Int = 70,
        speed: Int = 50,
        keyColors: [String] = ["00FF20", "0070FF", "DC00FF", "FF4800"]
    ) {
        self.mode = mode
        self.brightness = min(max(brightness, 0), 100)
        self.speed = min(max(speed, 1), 100)
        self.keyColors = Self.validatedColors(keyColors)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, brightness, speed, keyColors
    }

    /// Persisted settings are user-editable and survive upgrades. Decode them
    /// through the validating initializer so a malformed color array cannot
    /// crash the settings UI when it indexes the four physical keys.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: (try? values.decode(LightingMode.self, forKey: .mode)) ?? .rainbow,
            brightness: (try? values.decode(Int.self, forKey: .brightness)) ?? 70,
            speed: (try? values.decode(Int.self, forKey: .speed)) ?? 50,
            keyColors: (try? values.decode([String].self, forKey: .keyColors)) ?? []
        )
    }

    private static func validatedColors(_ colors: [String]) -> [String] {
        let defaults = ["00FF20", "0070FF", "DC00FF", "FF4800"]
        guard colors.count == 4 else { return defaults }
        return colors.enumerated().map { index, color in
            color.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) == nil
                ? defaults[index] : color.uppercased()
        }
    }
}
