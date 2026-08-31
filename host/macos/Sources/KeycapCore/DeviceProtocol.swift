// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum DeviceEvent: Equatable, Sendable {
    case hello(version: Int, firmware: String, board: String)
    case button(key: Int, isDown: Bool, sequence: UInt32)
    case gesture(key: Int, kind: GestureKind, sequence: UInt32)
    case error(code: String)
}

public enum GestureKind: String, Equatable, Sendable {
    case short = "SHORT"
    case long = "LONG"
    case double = "DOUBLE"
}

public extension DeviceEvent {
    /// Whether receiving this proves the device is still reading from the host.
    ///
    /// Only `HELLO` (and the bare `ALIVE` acknowledgement, which is not modelled
    /// as an event) is a reply to something the host sent. Button and gesture
    /// traffic is unsolicited: it proves the device-to-host direction works and
    /// says nothing about the other one. Counting it as liveness hides a
    /// half-open link, because a user pressing keys would keep a link the
    /// device can no longer hear from looking healthy.
    var provesDeviceIsListening: Bool {
        if case .hello = self { return true }
        return false
    }
}

public enum DeviceProtocolV1 {
    public static func parse(_ rawLine: String) -> DeviceEvent? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let type = fields.first else { return nil }

        switch type {
        case "HELLO" where fields.count == 4:
            guard let version = Int(fields[1]) else { return nil }
            return .hello(version: version, firmware: fields[2], board: fields[3])
        case "BUTTON" where fields.count == 4:
            guard let key = Int(fields[1]), (1...4).contains(key),
                  let sequence = UInt32(fields[3]),
                  fields[2] == "DOWN" || fields[2] == "UP" else { return nil }
            return .button(key: key, isDown: fields[2] == "DOWN", sequence: sequence)
        case "GESTURE" where fields.count == 4:
            guard let key = Int(fields[1]), (1...4).contains(key),
                  let kind = GestureKind(rawValue: fields[2]),
                  let sequence = UInt32(fields[3]) else { return nil }
            return .gesture(key: key, kind: kind, sequence: sequence)
        case "ERROR" where fields.count >= 2:
            return .error(code: fields.dropFirst().joined(separator: " "))
        default:
            return nil
        }
    }

    public static func leds(activeChoices: Int) -> String {
        let count = min(max(activeChoices, 0), 4)
        let colors = (0..<4).map { $0 < count ? "FFFFFF" : "000000" }
        return "LEDS \(colors.joined(separator: ","))\n"
    }
}

public enum DeviceProtocolV2 {
    public enum Status: Equatable, Sendable {
        case idle
        case waiting(activeChoices: Int, colorHex: String? = nil)
        case success
        case error
        case paused
    }

    public static func status(_ status: Status) -> String {
        switch status {
        case .idle: return "STATUS IDLE\n"
        case .waiting(let activeChoices, let colorHex):
            let count = min(max(activeChoices, 1), 4)
            let color = colorHex?.range(
                of: "^[0-9A-Fa-f]{6}$", options: .regularExpression
            ) == nil ? nil : colorHex?.uppercased()
            return "STATUS WAITING \(count)\(color.map { " \($0)" } ?? "")\n"
        case .success: return "STATUS SUCCESS\n"
        case .error: return "STATUS ERROR\n"
        case .paused: return "STATUS PAUSED\n"
        }
    }

    public static func lighting(_ profile: LightingProfile) -> String {
        let normalized = LightingProfile(
            mode: profile.mode,
            brightness: profile.brightness,
            speed: profile.speed,
            keyColors: profile.keyColors
        )
        return "LIGHTING \(normalized.mode.rawValue.uppercased()) "
            + "\(normalized.brightness) \(normalized.speed) "
            + "\(normalized.keyColors.joined(separator: ","))\n"
    }
}

public enum AgentLEDState: String, Codable, CaseIterable, Equatable, Sendable {
    case empty = "EMPTY"
    case idle = "IDLE"
    case working = "WORKING"
    case waiting = "WAITING"
    case completed = "DONE"
    case failed = "ERROR"
    case destructive = "RISK"
}

public enum DeviceProtocolV3 {
    public static func agents(_ states: [AgentLEDState]) -> String {
        let normalized = Array(states.prefix(4))
            + Array(repeating: .empty, count: max(0, 4 - states.count))
        return "AGENTS \(normalized.prefix(4).map(\.rawValue).joined(separator: ","))\n"
    }
}
