// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import KeycapHost

final class BrokerTokenTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keycap-token-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCreatesAndReusesAnOwnerOnlyToken() throws {
        let url = directory.appendingPathComponent("nested/token")
        let (created, createdURL) = try BrokerToken.loadOrCreate(at: url)

        XCTAssertEqual(createdURL, url)
        XCTAssertEqual(created.count, 64)
        XCTAssertFalse(created.contains("\n"))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        let (reused, _) = try BrokerToken.loadOrCreate(at: url)
        XCTAssertEqual(reused, created)
    }

    func testReplacesAnEmptyTokenFile() throws {
        let url = directory.appendingPathComponent("token")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("   \n".utf8).write(to: url)

        let (token, _) = try BrokerToken.loadOrCreate(at: url)
        XCTAssertEqual(token.count, 64)
    }

    func testGeneratesDistinctTokens() {
        XCTAssertNotEqual(BrokerToken.generate(), BrokerToken.generate())
    }
}
