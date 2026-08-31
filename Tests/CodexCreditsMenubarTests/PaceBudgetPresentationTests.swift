import AppKit
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

    @MainActor
    func testGraphBarsExposeUsageAtTheirHoverPoints() {
        let day = date(day: 1, hour: 0)
        let model = PaceDashboardModel(
            status: .underTarget,
            decision: "On target",
            remainingCredits: 90,
            remainingWorkdays: 5,
            todayUsage: 10,
            dailyTarget: 10,
            days: (0..<7).map {
                PaceDashboardDay(day: day.addingTimeInterval(Double($0) * 86_400), actualUsage: 10)
            },
            billingPeriod: PaceDashboardBillingPeriod(
                totalUsage: 10,
                periodLimit: 100,
                resetAt: nil,
                usageText: "Used 10 of 100",
                resetText: "Reset unavailable",
                days: [PaceDashboardPeriodDay(day: day, actualUsage: 7, previousPeriodUsage: 5)]
            )
        )
        let view = PaceDashboardView(model: model)

        XCTAssertTrue(view.hoverText(at: NSPoint(x: 25, y: 153))?.contains("10 credits used") == true)
        XCTAssertTrue(view.hoverText(at: NSPoint(x: 20, y: 35))?.contains("prior period 5 credits") == true)
        XCTAssertTrue(view.hoverText(at: NSPoint(x: 180, y: 35))?.contains("current period 7 credits") == true)
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
