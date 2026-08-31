// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The per-install shared secret that local adapters present to the broker.
///
/// The token lives beside the other Application Support state so any adapter
/// running as the same user can read it, and is created with owner-only
/// permissions so other accounts on the machine cannot.
enum BrokerToken {
    enum TokenError: Error, CustomStringConvertible {
        case couldNotPersist(URL, Error)

        var description: String {
            switch self {
            case .couldNotPersist(let url, let error):
                return "Could not write the broker token to \(url.path): \(error)"
            }
        }
    }

    static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["KEYCAP_TOKEN_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent("Keycap Context/token")
    }

    static func loadOrCreate(at url: URL? = nil) throws -> (token: String, url: URL) {
        let url = url ?? defaultURL()
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                do {
                    try restrictPermissions(at: url)
                } catch {
                    throw TokenError.couldNotPersist(url, error)
                }
                return (trimmed, url)
            }
        }

        let token = generate()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("\(token)\n".utf8).write(to: url, options: .atomic)
            try restrictPermissions(at: url)
        } catch {
            throw TokenError.couldNotPersist(url, error)
        }
        return (token, url)
    }

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// `Data.write(options: .atomic)` replaces the file, so the mode is applied
    /// after every write rather than only at creation.
    private static func restrictPermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }
}
