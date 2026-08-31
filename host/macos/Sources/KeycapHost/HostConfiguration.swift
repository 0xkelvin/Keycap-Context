// SPDX-License-Identifier: Apache-2.0
import Foundation

struct HostConfiguration: Equatable {
    let port: UInt16
    let serialPath: String?
    let autodetectSerial: Bool
    let overlayPosition: OverlayPosition

    static func parse(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> HostConfiguration {
        var port = try parsePort(environment["KEYCAP_PORT"] ?? "47821")
        var serialPath = environment["KEYCAP_SERIAL_PATH"]
        var autodetectSerial = environment["KEYCAP_SERIAL_AUTODETECT"] != "0"
        var overlayPosition = OverlayPosition(
            rawValue: environment["KEYCAP_OVERLAY_POSITION"] ?? "top-center"
        ) ?? .topCenter

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--port":
                index += 1
                guard index < arguments.count else { throw ConfigurationError.missingValue("--port") }
                port = try parsePort(arguments[index])
            case "--serial":
                index += 1
                guard index < arguments.count else { throw ConfigurationError.missingValue("--serial") }
                serialPath = arguments[index]
                autodetectSerial = false
            case "--no-serial":
                serialPath = nil
                autodetectSerial = false
            case "--overlay-position":
                index += 1
                guard index < arguments.count else {
                    throw ConfigurationError.missingValue("--overlay-position")
                }
                guard let value = OverlayPosition(rawValue: arguments[index]) else {
                    throw ConfigurationError.invalidOverlayPosition(arguments[index])
                }
                overlayPosition = value
            default:
                break
            }
            index += 1
        }

        return HostConfiguration(
            port: port,
            serialPath: serialPath,
            autodetectSerial: autodetectSerial,
            overlayPosition: overlayPosition
        )
    }

    private static func parsePort(_ value: String) throws -> UInt16 {
        guard let port = UInt16(value), port > 0 else {
            throw ConfigurationError.invalidPort(value)
        }
        return port
    }
}

enum OverlayPosition: String, CaseIterable, Equatable {
    case topLeft = "top-left"
    case topCenter = "top-center"
    case topRight = "top-right"
}

enum ConfigurationError: Error, CustomStringConvertible, Equatable {
    case missingValue(String)
    case invalidPort(String)
    case invalidOverlayPosition(String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "Missing value for \(flag)"
        case .invalidPort(let value): return "Invalid broker port: \(value)"
        case .invalidOverlayPosition(let value):
            return "Invalid overlay position: \(value) (expected top-left, top-center, or top-right)"
        }
    }
}
