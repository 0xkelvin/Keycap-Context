// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum LightingMode: String, Codable, CaseIterable, Sendable {
    case rainbow
    case wave
    case breathing
    case reactive
    case staticColor = "static"
    case off

    public var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .wave: return "Color Wave"
        case .breathing: return "Breathing"
        case .reactive: return "Reactive"
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
