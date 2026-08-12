import XCTest
@testable import CodexCreditsMenubar

final class SpendControlTests: XCTestCase {
    func testMenuLinesUseCompactWholeCreditFormattingWithoutChangingPercentOrDate() throws {
        let data = Data(#"{"spend_control":{"individual_limit":{"limit":8569.97,"used":2345,"remaining":999.7,"remaining_percent":88.5,"reset_at":"2026-08-01"}}}"#.utf8)
        let control = try JSONDecoder().decode(UsageResponse.self, from: data).spendControl

        XCTAssertEqual(control.map { Array($0.menuLines.prefix(4)) }, ["Spend limit: 8.6k", "Spent: 2.3k", "Remaining: 1,000", "Remaining: 88.5%"])
        XCTAssertEqual(control?.menuLines.last, "Reset: 2026-08-01")
    }

    func testUsesNestedIndividualLimitAndIgnoresTopLevelIndividualLimit() throws {
        let json = """
        {
          "individual_limit": {"limit": "999", "used": "1", "remaining": "998"},
          "spend_control": {
            "reached": false,
            "individual_limit": {
              "source": "plan",
              "limit": "100",
              "used": "25",
              "remaining": "75",
              "used_percent": 25,
              "remaining_percent": 75,
              "reset_after_seconds": 3600,
              "reset_at": "2026-08-01"
            }
          }
        }
        """.data(using: .utf8)!
        let actual = try JSONDecoder().decode(UsageResponse.self, from: json).spendControl
        XCTAssertEqual(actual?.limit, 100)
        XCTAssertEqual(actual?.used, 25)
        XCTAssertEqual(actual?.remaining, 75)
        XCTAssertEqual(actual?.remainingPercent, 75)
        XCTAssertEqual(actual?.usagePercent, 25)
        XCTAssertEqual(actual?.resetAt, "2026-08-01")
    }

    func testComputesMissingValuesAndFormatsNumericResetAtLocally() throws {
        let resetAt = 1_800_000_000.0
        let json = """
        {"spend_control":{"individual_limit":{"limit":"100","used":25,"reset_at":\(resetAt)}}}
        """.data(using: .utf8)!
        let actual = try JSONDecoder().decode(UsageResponse.self, from: json).spendControl

        XCTAssertEqual(actual?.remaining, 75)
        XCTAssertEqual(actual?.remainingPercent, 75)
        XCTAssertEqual(actual?.usagePercent, 25)
        let expectedReset = DateFormatter.localizedString(from: Date(timeIntervalSince1970: resetAt), dateStyle: .medium, timeStyle: .short)
        XCTAssertEqual(actual?.menuLines.last, "Reset: \(expectedReset)")
    }

    func testConfigurationHonorsOverrides() {
        let config = RequestConfiguration(environment: ["CODEX_AUTH_FILE": "/tmp/auth.json", "CODEX_CHATGPT_BASE_URL": "https://example.test/base/"], homeDirectory: URL(fileURLWithPath: "/unused"))
        XCTAssertEqual(config.authFileURL.path, "/tmp/auth.json")
        XCTAssertEqual(config.usageURL.absoluteString, "https://example.test/base/wham/usage")
    }

    func testUsageSimulationProgressesAndClamps() {
        XCTAssertEqual(UsageSimulation.usagePercent(elapsed: 0), 0)
        XCTAssertEqual(UsageSimulation.usagePercent(elapsed: 7.5), 25)
        XCTAssertEqual(UsageSimulation.usagePercent(elapsed: 15), 50)
        XCTAssertEqual(UsageSimulation.usagePercent(elapsed: 30), 100)
        XCTAssertEqual(UsageSimulation.usagePercent(elapsed: 60), 100)
    }

    func testStatusIconUsesClampedDailyTargetUsageAndPreservesUnavailableState() {
        XCTAssertEqual(StatusIconPresentation.dailyTargetUsagePercent(dashboard(todayUsage: 25, dailyTarget: 100)), 25)
        XCTAssertEqual(StatusIconPresentation.dailyTargetUsagePercent(dashboard(todayUsage: 125, dailyTarget: 100)), 100)
        XCTAssertNil(StatusIconPresentation.dailyTargetUsagePercent(dashboard(todayUsage: nil, dailyTarget: 100)))
        XCTAssertEqual(StatusIconPresentation.tooltip(dailyTargetUsagePercent: 25, simulatedBillingUsagePercent: nil), "Codex daily target: 25% used today")
        XCTAssertEqual(StatusIconPresentation.tooltip(dailyTargetUsagePercent: nil, simulatedBillingUsagePercent: nil), "Codex daily target unavailable")
    }

    private func dashboard(todayUsage: Double?, dailyTarget: Double?) -> PaceDashboardModel {
        PaceDashboardModel(
            status: .unavailable,
            decision: "Unavailable",
            remainingCredits: nil,
            remainingWorkdays: nil,
            todayUsage: todayUsage,
            dailyTarget: dailyTarget,
            days: []
        )
    }
}
