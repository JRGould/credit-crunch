import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class UsageMetricsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCalculatesDayBurnAndProjectionWithinResetPeriod() {
        let snapshots = [snapshot(day: 3, hour: 1, used: 10), snapshot(day: 3, hour: 13, used: 16)]
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: date(day: 3, hour: 14), calendar: utc)

        XCTAssertEqual(metrics.currentDayUsage, 6)
        XCTAssertEqual(metrics.dailyBurnRate, 12)
        XCTAssertEqual(metrics.projectedExhaustionDate, date(day: 10, hour: 13))
    }

    func testDoesNotCrossCalendarOrResetBoundary() {
        let snapshots = [
            snapshot(day: 2, hour: 23, used: 90, reset: "old"),
            snapshot(day: 3, hour: 1, used: 2, reset: "new"),
            snapshot(day: 3, hour: 13, used: 8, reset: "new")
        ]
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: date(day: 3, hour: 14), calendar: utc)

        XCTAssertEqual(metrics.currentDayUsage, 6)
        XCTAssertEqual(metrics.dailyBurnRate, 12)
    }

    func testSparseOrNonPositiveHistoryHasNoBurnOrProjection() {
        let sparse = UsageMetricsEngine.calculate(snapshots: [snapshot(day: 3, hour: 1, used: 10)], now: date(day: 3, hour: 2), calendar: utc)
        XCTAssertNil(sparse.dailyBurnRate)
        XCTAssertNil(sparse.projectedExhaustionDate)

        let decreasing = UsageMetricsEngine.calculate(snapshots: [snapshot(day: 3, hour: 1, used: 10), snapshot(day: 3, hour: 2, used: 8)], now: date(day: 3, hour: 3), calendar: utc)
        XCTAssertNil(decreasing.dailyBurnRate)
        XCTAssertNil(decreasing.projectedExhaustionDate)
    }

    func testForecastUsesCompletedSamePeriodDaysAndMonFriPace() {
        let snapshots = [
            snapshot(day: 4, hour: 20, used: 0, reset: "2026-01-13"),
            snapshot(day: 5, hour: 20, used: 10, reset: "2026-01-13"),
            snapshot(day: 6, hour: 20, used: 30, reset: "2026-01-13"),
            snapshot(day: 7, hour: 20, used: 40, reset: "2026-01-13"),
            snapshot(day: 8, hour: 10, used: 40, reset: "2026-01-13")
        ]
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: date(day: 8, hour: 12), calendar: utc)

        XCTAssertEqual(metrics.calendarDayBaseline, 10)
        XCTAssertEqual(metrics.workdayIncrement, 0)
        XCTAssertEqual(metrics.remainingCredits, 60)
        XCTAssertEqual(metrics.calendarDaysUntilReset, 5)
        XCTAssertEqual(metrics.workingDaysUntilReset, 3)
        XCTAssertEqual(metrics.sustainableWorkdayIncrement!, 10.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.paceDelta!, 10.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.projectedResetBalance, 10)
        XCTAssertEqual(metrics.estimateConfidence, .high)
    }

    func testForecastIsUnavailableWhenBaselineReserveUsesRemainingCredits() {
        let snapshots = [
            snapshot(day: 4, hour: 20, used: 20, reset: "2026-01-13"),
            snapshot(day: 5, hour: 20, used: 30, reset: "2026-01-13"),
            snapshot(day: 6, hour: 20, used: 40, reset: "2026-01-13"),
            snapshot(day: 7, hour: 20, used: 50, reset: "2026-01-13"),
            snapshot(day: 8, hour: 10, used: 50, reset: "2026-01-13")
        ]
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: date(day: 8, hour: 12), calendar: utc)

        XCTAssertEqual(metrics.calendarDayBaseline, 10)
        XCTAssertEqual(metrics.workdayIncrement, 0)
        XCTAssertEqual(metrics.remainingCredits, 50)
        XCTAssertNil(metrics.sustainableWorkdayIncrement)
        XCTAssertNil(metrics.paceDelta)
        XCTAssertNil(metrics.projectedResetBalance)
    }

    func testSingleCompletedIntervalUsesProvisionalFallback() {
        let snapshots = [
            snapshot(day: 6, hour: 20, used: 10, reset: "2026-01-13"),
            snapshot(day: 7, hour: 20, used: 20, reset: "2026-01-13"),
            snapshot(day: 8, hour: 10, used: 20, reset: "2026-01-13")
        ]
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: date(day: 8, hour: 12), calendar: utc)

        XCTAssertEqual(metrics.calendarDayBaseline, 10)
        XCTAssertEqual(metrics.workdayIncrement, 0)
        XCTAssertEqual(metrics.paceDelta, 10)
        XCTAssertEqual(metrics.projectedResetBalance, 30)
        XCTAssertEqual(metrics.estimateConfidence, .provisional)
        XCTAssertNil(metrics.projectedExhaustionDate)
        XCTAssertEqual(metrics.projectedExhaustionStatus, .afterReset)
    }

    func testSingleSnapshotUsesZeroProvisionalFallbackWhenBudgetMathIsAvailable() {
        let metrics = UsageMetricsEngine.calculate(
            snapshots: [snapshot(day: 8, hour: 10, used: 20, reset: "2026-01-13")],
            now: date(day: 8, hour: 12),
            calendar: utc
        )

        XCTAssertEqual(metrics.dailyBurnRate, 0)
        XCTAssertEqual(metrics.calendarDayBaseline, 0)
        XCTAssertEqual(metrics.workdayIncrement, 0)
        XCTAssertEqual(metrics.sustainableWorkdayIncrement!, 80.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.estimateConfidence, .provisional)
        XCTAssertNil(metrics.projectedExhaustionDate)
        XCTAssertEqual(metrics.projectedExhaustionStatus, .noExhaustionWithinPeriod)
    }

    func testIncludesFullWeekdayResetDayAtFivePMInWorkdayCapacity() {
        let reset = "2026-01-06T17:00:00Z"
        let snapshot = UsageSnapshot(
            collectedAt: date(day: 5, hour: 10),
            limit: 10_000,
            used: 2_700,
            remaining: 7_300,
            remainingPercent: 73,
            resetAt: reset
        )

        let metrics = UsageMetricsEngine.calculate(snapshots: [snapshot], now: date(day: 5, hour: 12), calendar: utc)

        XCTAssertEqual(metrics.workingDaysUntilReset, 1)
        XCTAssertEqual(metrics.workdayCapacityUntilReset, 2)
        XCTAssertEqual(metrics.sustainableWorkdayIncrement, 3_650)
    }

    func testUsesLocalTimezoneForFractionalWeekdayResetCapacity() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = pacific.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: 12))!
        let snapshot = UsageSnapshot(
            collectedAt: pacific.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: 10))!,
            limit: 10_000,
            used: 2_700,
            remaining: 7_300,
            remainingPercent: 73,
            resetAt: "2026-01-07T21:00:00Z"
        )

        let metrics = UsageMetricsEngine.calculate(snapshots: [snapshot], now: now, calendar: pacific)

        XCTAssertEqual(metrics.workdayCapacityUntilReset!, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(metrics.sustainableWorkdayIncrement!, 7_300.0 / 1.5, accuracy: 0.000_001)
    }

    private func snapshot(day: Int, hour: Int, used: Double, reset: String = "reset") -> UsageSnapshot {
        UsageSnapshot(collectedAt: date(day: day, hour: hour), limit: 100, used: used, remaining: 100 - used, remainingPercent: 100 - used, resetAt: reset)
    }

    private func date(day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }
}
