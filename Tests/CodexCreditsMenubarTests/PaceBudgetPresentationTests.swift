import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class PaceBudgetPresentationTests: XCTestCase {
    func testShowsReadablePaceGuidanceAndDaysLeft() {
        let snapshots = [
            snapshot(day: 4, used: 0), snapshot(day: 5, used: 10),
            snapshot(day: 6, used: 30), snapshot(day: 7, used: 40),
            snapshot(day: 8, used: 40)
        ]

        let lines = UsagePresentation.metricLines(snapshots: snapshots, now: date(day: 8, hour: 12))

        XCTAssertTrue(lines.contains("Days left: 5 calendar, 3 workdays"))
        XCTAssertTrue(lines.contains("Pace: pull back by 3/workday"))
        XCTAssertTrue(lines.contains("Projected reset balance: 10"))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func snapshot(day: Int, used: Double) -> UsageSnapshot {
        UsageSnapshot(collectedAt: date(day: day, hour: 20), limit: 100, used: used, remaining: 100 - used, remainingPercent: 100 - used, resetAt: "2026-01-13")
    }

    private func date(day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }
}
