import Foundation
import XCTest
@testable import CodexCreditsMenubar

private final class UsageFixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func install(responder: @escaping (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        self.responder = responder
    }

    static func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        responder = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let responder = Self.responder
        Self.lock.unlock()

        guard let responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UsageServiceFixtureTests: XCTestCase {
    func testFetchSpendControlUsesTemporaryAuthAndFixtureEndpoint() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-credits-menubar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let authURL = temporaryDirectory.appendingPathComponent("auth.json")
        try Data(#"{"tokens":{"access_token":"fixture-token","account_id":"fixture-account"}}"#.utf8)
            .write(to: authURL)

        let usageURL = URL(string: "https://fixture.test/backend-api/wham/usage")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        UsageFixtureURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url, usageURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "CodexCreditsMenubar")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "fixture-account")

            let response = HTTPURLResponse(
                url: usageURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"spend_control":{"individual_limit":{"limit":100,"used":25,"remaining":75,"remaining_percent":75,"reset_at":"2026-08-01"}}}"#.utf8)
            return (response, body)
        }
        defer { UsageFixtureURLProtocol.uninstall() }

        let service = UsageService(
            configuration: RequestConfiguration(
                environment: ["CODEX_AUTH_FILE": authURL.path, "CODEX_CHATGPT_BASE_URL": "https://fixture.test/backend-api"],
                homeDirectory: temporaryDirectory
            ),
            session: session
        )

        let spendControl = try await service.fetchSpendControl()
        XCTAssertEqual(spendControl.limit, 100)
        XCTAssertEqual(spendControl.used, 25)
        XCTAssertEqual(spendControl.remaining, 75)
        XCTAssertEqual(spendControl.remainingPercent, 75)
        XCTAssertEqual(spendControl.resetAt, "2026-08-01")
    }
}
