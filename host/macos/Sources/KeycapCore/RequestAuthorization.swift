// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum AuthorizationDecision: Equatable, Sendable {
    case allowed
    /// The `Host` header did not name the loopback interface.
    case untrustedHost
    /// The request carries browser fetch metadata, so it originated from a web
    /// page rather than a local adapter.
    case crossSite
    /// The shared token was absent or did not match.
    case unauthorized
}

/// Authorizes local adapter traffic.
///
/// Binding to `127.0.0.1` only proves the peer is on this machine. It does not
/// distinguish a trusted agent adapter from any other local process, nor from a
/// web page the user happens to be visiting: a CORS-simple `POST` reaches the
/// broker with a loopback `Host` header like any other client. Requests
/// therefore carry a per-install token, and anything wearing browser fetch
/// metadata is refused outright.
public enum RequestAuthorization {
    public static func evaluate(
        headers: [String: String],
        token: String
    ) -> AuthorizationDecision {
        let headers = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        guard isLoopbackHost(headers["host"]) else { return .untrustedHost }
        guard !isBrowserOriginated(headers) else { return .crossSite }

        // An unwritable token file must fail closed rather than open.
        guard !token.isEmpty, let presented = presentedToken(headers),
              constantTimeEquals(presented, token) else {
            return .unauthorized
        }
        return .allowed
    }

    static func isLoopbackHost(_ value: String?) -> Bool {
        guard let value = value?
            .trimmingCharacters(in: .whitespaces)
            .lowercased(), !value.isEmpty else { return false }
        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]") else { return false }
            return String(value[value.index(after: value.startIndex)..<end]) == "::1"
        }
        let host = value.split(separator: ":", maxSplits: 1).first.map(String.init) ?? value
        return host == "127.0.0.1" || host == "localhost"
    }

    static func isBrowserOriginated(_ headers: [String: String]) -> Bool {
        if let origin = headers["origin"]?.trimmingCharacters(in: .whitespaces),
           !origin.isEmpty {
            return true
        }
        if let site = headers["sec-fetch-site"]?
            .trimmingCharacters(in: .whitespaces).lowercased(), site != "none" {
            return true
        }
        return false
    }

    static func presentedToken(_ headers: [String: String]) -> String? {
        if let header = headers["x-keycap-token"]?.trimmingCharacters(in: .whitespaces),
           !header.isEmpty {
            return header
        }
        guard let authorization = headers["authorization"]?
            .trimmingCharacters(in: .whitespaces) else { return nil }
        let parts = authorization.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Compares without leaking the position of the first differing byte.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(left.count == right.count ? 0 : 1)
        for index in 0..<max(left.count, right.count) {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }
}
