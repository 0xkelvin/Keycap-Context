// SPDX-License-Identifier: Apache-2.0
import Foundation

enum BrokerStatus: Equatable {
    case starting
    case listening(UInt16)
    case failed(String)
}

enum DeviceStatus: Equatable {
    case disabled
    case disconnected
    case connecting(String)
    case connected(String)
    case failed(String)

    var healthValue: String {
        switch self {
        case .disabled: return "disabled"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .failed: return "error"
        }
    }
}

struct HostStatus: Equatable {
    var broker: BrokerStatus = .starting
    var device: DeviceStatus = .disconnected
    var queueCount = 0
    var activeAgent: String?
    var isPaused = false
}

struct HealthSnapshot: Codable, Equatable {
    let status: String
    let port: UInt16
    let paused: Bool
    let queueCount: Int
    let activeAgent: String?
    let device: String
}
