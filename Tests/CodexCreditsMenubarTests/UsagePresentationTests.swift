import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class UsagePresentationTests: XCTestCase {
    func testShowsExplicitInsufficientStatesWithoutHistory() {
        XCTAssertEqual(UsagePresentation.metricLines(snapshots: []), ["History: no local samples yet"])
        XCTAssertEqual(UsagePresentation.historyLines(snapshots: []), ["Recent history: no local samples yet"])
    }

    func testShowsMetricInsufficientHistoryForSingleSample() {
        let snapshot = UsageSnapshot(collectedAt: Date(), limit: 100, used: 10, remaining: 90, remainingPercent: 90, resetAt: "reset")
        let lines = UsagePresentation.metricLines(snapshots: [snapshot])
        XCTAssertTrue(lines.contains("Daily burn: insufficient history"))
        XCTAssertTrue(lines.contains("Projected exhaustion: insufficient history"))
    }

    func testMarksEveryProvisionalEstimateWithLowConfidenceIcon() {
        let now = date(day: 8, hour: 12)
        let snapshot = UsageSnapshot(collectedAt: date(day: 8, hour: 10), limit: 100, used: 20, remaining: 80, remainingPercent: 80, resetAt: "2026-01-13")

        let lines = UsagePresentation.metricLines(snapshots: [snapshot], now: now)

        XCTAssertTrue(lines.contains("Daily burn: 0 ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Projected exhaustion: no exhaustion within period ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Calendar baseline: 0/day ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Workday pace: 0/workday ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Sustainable workday pace: 27/workday ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Pace: pull back by 27/workday ⚠︎ low confidence"))
        XCTAssertTrue(lines.contains("Projected reset balance: 80 ⚠︎ low confidence"))
    }

    func testDashboardShowsOverTargetWithoutTimeBasedRemainder() {
        let now = date(day: 8, hour: 12)
        let snapshots = [
            snapshot(day: 8, hour: 8, used: 40),
            snapshot(day: 8, hour: 12, used: 70)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dashboard.dailyTarget, 10)
        XCTAssertEqual(dashboard.todayUsage, 30)
        XCTAssertEqual(dashboard.status, .overTarget)
        XCTAssertEqual(dashboard.decision, "20 credits over target")
        XCTAssertEqual(dashboard.progress.fillFraction, 1)
        XCTAssertEqual(dashboard.progress.usageText, "30 used today")
        XCTAssertEqual(dashboard.progress.targetText, "of 10 target")
        XCTAssertEqual(dashboard.progress.statusText, "20 credits over target")
        XCTAssertFalse(dashboard.decision.localizedCaseInsensitiveContains("hour"))
        XCTAssertFalse(dashboard.decision.localizedCaseInsensitiveContains("minute"))
    }

    func testDashboardShowsRemainingHeadroomWhenUnderTarget() {
        let now = date(day: 8, hour: 12)
        let snapshots = [
            snapshot(day: 8, hour: 8, used: 40),
            snapshot(day: 8, hour: 12, used: 46)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dashboard.dailyTarget, 18)
        XCTAssertEqual(dashboard.todayUsage, 6)
        XCTAssertEqual(dashboard.status, .underTarget)
        XCTAssertEqual(dashboard.decision, "12 credits under target")
        XCTAssertEqual(dashboard.progress.fillFraction ?? -1, 1 / 3, accuracy: 0.000_001)
        XCTAssertEqual(dashboard.progress.statusText, "12 credits under target")
    }

    func testDashboardKeepsSparseHistoryExplicitAndBuildsSevenDays() {
        let now = date(day: 8, hour: 12)
        let dashboard = UsagePresentation.paceDashboard(snapshots: [snapshot(day: 8, hour: 10, used: 20)], now: now, calendar: utc)

        XCTAssertEqual(dashboard.status, .unavailable)
        XCTAssertEqual(dashboard.decision, "Today's pace is not available yet")
        XCTAssertEqual(dashboard.days.count, 7)
        XCTAssertNil(dashboard.days.last?.actualUsage)
    }

    func testDashboardRetainsPriorPeriodUsageWithoutInventingResetDayUsage() {
        let now = date(day: 8, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 5, hour: 18), limit: 100, used: 10, remaining: 90, remainingPercent: 90, resetAt: "2026-01-07T00:00:00Z"),
            UsageSnapshot(collectedAt: date(day: 6, hour: 18), limit: 100, used: 20, remaining: 80, remainingPercent: 80, resetAt: "2026-01-07T00:00:00Z"),
            snapshot(day: 7, hour: 12, used: 4),
            snapshot(day: 8, hour: 8, used: 40),
            snapshot(day: 8, hour: 12, used: 46)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dayUsage(on: 6, in: dashboard), 10)
        XCTAssertNil(dayUsage(on: 7, in: dashboard))
        XCTAssertEqual(dayUsage(on: 8, in: dashboard), 6)
        XCTAssertEqual(dashboard.todayUsage, 6)
        XCTAssertEqual(dashboard.dailyTarget, 18)
    }

    func testDashboardKeepsDailyHistoryWhenTheEndpointVarysResetSeconds() {
        let now = date(day: 8, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 6, hour: 18), limit: 100, used: 10, remaining: 90, remainingPercent: 90, resetAt: "2026-01-13T00:00:00Z"),
            UsageSnapshot(collectedAt: date(day: 7, hour: 18), limit: 100, used: 17, remaining: 83, remainingPercent: 83, resetAt: "2026-01-13T00:00:01Z"),
            UsageSnapshot(collectedAt: date(day: 8, hour: 8), limit: 100, used: 22, remaining: 78, remainingPercent: 78, resetAt: "2026-01-13T00:00:02Z"),
            UsageSnapshot(collectedAt: date(day: 8, hour: 12), limit: 100, used: 26, remaining: 74, remainingPercent: 74, resetAt: "2026-01-13T00:00:02Z")
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dayUsage(on: 7, in: dashboard), 7)
        XCTAssertEqual(dayUsage(on: 8, in: dashboard), 4)
        XCTAssertEqual(dashboard.todayUsage, 4)
    }

    func testDashboardLeavesTheDayAfterAMixedResetDayUnavailable() {
        let now = date(day: 9, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 7, hour: 12), limit: 100, used: 20, remaining: 80, remainingPercent: 80, resetAt: "2026-01-07T17:00:00Z"),
            snapshot(day: 7, hour: 18, used: 2),
            snapshot(day: 8, hour: 18, used: 8),
            snapshot(day: 9, hour: 8, used: 10),
            snapshot(day: 9, hour: 12, used: 12)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertNil(dayUsage(on: 8, in: dashboard))
        XCTAssertEqual(dayUsage(on: 9, in: dashboard), 2)
    }

    func testDashboardDividesRemainingCreditsAcrossFullWeekdayResetDay() {
        let now = date(day: 5, hour: 12)
        let snapshots = [
            resetSnapshot(day: 5, hour: 8, used: 2_650),
            resetSnapshot(day: 5, hour: 12, used: 2_700)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dashboard.remainingWorkdays, 2)
        XCTAssertEqual(dashboard.dailyTarget, 3_650)
        XCTAssertEqual(dashboard.progress.targetText, "of 3.7k target")
    }

    func testDashboardKeepsResetDayTargetFixedAsUsageRises() {
        let now = date(day: 6, hour: 12)
        let snapshots = [
            resetSnapshot(day: 6, hour: 9, used: 2_700),
            resetSnapshot(day: 6, hour: 12, used: 2_750)
        ]

        let dashboard = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc)

        XCTAssertEqual(dashboard.remainingCredits, 7_250)
        XCTAssertEqual(dashboard.dailyTarget, 7_300)
        XCTAssertEqual(dashboard.todayUsage, 50)
        XCTAssertEqual(dashboard.dailyTarget! - dashboard.todayUsage!, dashboard.remainingCredits)
        XCTAssertEqual(dashboard.status, .underTarget)
        XCTAssertEqual(dashboard.decision, "7.3k credits under target")
    }

    func testDashboardDoesNotInventResetDayTargetFromOneSample() {
        let now = date(day: 6, hour: 12)
        let dashboard = UsagePresentation.paceDashboard(
            snapshots: [resetSnapshot(day: 6, hour: 9, used: 2_700)],
            now: now,
            calendar: utc
        )

        XCTAssertNil(dashboard.dailyTarget)
        XCTAssertEqual(dashboard.status, .unavailable)
    }

    func testDashboardShowsBillingPeriodUsageAndResetFromLatestSnapshot() {
        let now = date(day: 8, hour: 12)
        let dashboard = UsagePresentation.paceDashboard(
            snapshots: [
                snapshot(day: 8, hour: 8, used: 40),
                snapshot(day: 8, hour: 12, used: 46)
            ],
            now: now,
            calendar: utc
        )

        XCTAssertEqual(dashboard.billingPeriod.totalUsage, 46)
        XCTAssertEqual(dashboard.billingPeriod.periodLimit, 100)
        XCTAssertEqual(dashboard.billingPeriod.resetAt, date(day: 13, hour: 0))
        XCTAssertEqual(dashboard.billingPeriod.usageText, "Used  46 of 100")
    }

    func testDashboardKeepsBillingPeriodFieldsExplicitlyUnavailable() {
        let dashboard = UsagePresentation.paceDashboard(snapshots: [], now: date(day: 8, hour: 12), calendar: utc)

        XCTAssertNil(dashboard.billingPeriod.totalUsage)
        XCTAssertNil(dashboard.billingPeriod.periodLimit)
        XCTAssertNil(dashboard.billingPeriod.resetAt)
        XCTAssertEqual(dashboard.billingPeriod.usageText, "Used  —")
        XCTAssertEqual(dashboard.billingPeriod.resetText, "Resets  unavailable")
    }

    func testBillingPeriodSlotsExtendThroughResetAndLeaveFutureDaysUnfilled() {
        let now = date(day: 8, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 6, hour: 18), limit: 100, used: 20, remaining: 80, remainingPercent: 80, resetAt: "2026-01-07"),
            snapshot(day: 8, hour: 8, used: 40),
            snapshot(day: 8, hour: 12, used: 46)
        ]

        let slots = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc).billingPeriod.days

        XCTAssertEqual(slots.map { utc.component(.day, from: $0.day) }, Array(7...13))
        XCTAssertEqual(slots.first { utc.component(.day, from: $0.day) == 8 }?.actualUsage, 6)
        XCTAssertTrue(slots.filter { utc.component(.day, from: $0.day) > 8 }.allSatisfy { $0.actualUsage == nil })
    }

    func testBillingPeriodAlignsPriorUsageByWeekdayOccurrence() {
        let now = date(day: 24, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(month: 12, day: 29, hour: 18), limit: 100, used: 90, remaining: 10, remainingPercent: 10, resetAt: "2025-12-30"),
            UsageSnapshot(collectedAt: date(day: 8, hour: 18), limit: 100, used: 10, remaining: 90, remainingPercent: 90, resetAt: "2026-01-10"),
            UsageSnapshot(collectedAt: date(day: 9, hour: 18), limit: 100, used: 17, remaining: 83, remainingPercent: 83, resetAt: "2026-01-10"),
            UsageSnapshot(collectedAt: date(day: 22, hour: 18), limit: 100, used: 100, remaining: 0, remainingPercent: 0, resetAt: "2026-02-05"),
            UsageSnapshot(collectedAt: date(day: 23, hour: 8), limit: 100, used: 120, remaining: -20, remainingPercent: -20, resetAt: "2026-02-05"),
            UsageSnapshot(collectedAt: date(day: 23, hour: 12), limit: 100, used: 130, remaining: -30, remainingPercent: -30, resetAt: "2026-02-05"),
            UsageSnapshot(collectedAt: date(day: 24, hour: 12), limit: 100, used: 140, remaining: -40, remainingPercent: -40, resetAt: "2026-02-05")
        ]

        let slots = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc).billingPeriod.days
        let januaryTwentyThird = slots.first { utc.component(.day, from: $0.day) == 23 }

        XCTAssertEqual(januaryTwentyThird?.actualUsage, 30)
        XCTAssertEqual(januaryTwentyThird?.previousPeriodUsage, 7)
    }

    func testBillingPeriodLeavesMixedResetBoundaryAndFollowingDayUnavailable() {
        let now = date(day: 9, hour: 12)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 7, hour: 9), limit: 100, used: 99, remaining: 1, remainingPercent: 1, resetAt: "2026-01-07"),
            UsageSnapshot(collectedAt: date(day: 7, hour: 18), limit: 100, used: 4, remaining: 96, remainingPercent: 96, resetAt: "2026-01-13"),
            snapshot(day: 8, hour: 18, used: 10),
            snapshot(day: 9, hour: 8, used: 12),
            snapshot(day: 9, hour: 12, used: 15)
        ]

        let slots = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc).billingPeriod.days

        XCTAssertNil(slots.first { utc.component(.day, from: $0.day) == 7 }?.actualUsage)
        XCTAssertNil(slots.first { utc.component(.day, from: $0.day) == 8 }?.actualUsage)
        XCTAssertEqual(slots.first { utc.component(.day, from: $0.day) == 9 }?.actualUsage, 3)
    }

    func testBillingPeriodShowsPostResetUsageForTheCurrentMixedDay() {
        let now = date(day: 7, hour: 19)
        let snapshots = [
            UsageSnapshot(collectedAt: date(day: 7, hour: 9), limit: 100, used: 99, remaining: 1, remainingPercent: 1, resetAt: "2026-01-07"),
            UsageSnapshot(collectedAt: date(day: 7, hour: 18), limit: 100, used: 4, remaining: 96, remainingPercent: 96, resetAt: "2026-01-13"),
            UsageSnapshot(collectedAt: date(day: 7, hour: 19), limit: 100, used: 10, remaining: 90, remainingPercent: 90, resetAt: "2026-01-13")
        ]

        let slots = UsagePresentation.paceDashboard(snapshots: snapshots, now: now, calendar: utc).billingPeriod.days

        XCTAssertEqual(slots.first { utc.component(.day, from: $0.day) == 7 }?.actualUsage, 6)
    }

    func testImportedDailyUsageBackfillsMissingSevenDayAndPriorPeriodBars() {
        let now = date(day: 8, hour: 12)
        let dashboard = UsagePresentation.paceDashboard(
            snapshots: [
                snapshot(day: 8, hour: 8, used: 40),
                snapshot(day: 8, hour: 12, used: 46)
            ],
            importedDailyUsage: [
                AnalyticsDailyUsage(day: date(day: 2, hour: 0), credits: 7),
                AnalyticsDailyUsage(day: date(month: 12, day: 11, hour: 0), credits: 9)
            ],
            now: now,
            calendar: utc
        )

        XCTAssertEqual(dayUsage(on: 2, in: dashboard), 7)
        XCTAssertEqual(dashboard.billingPeriod.days.first?.previousPeriodUsage, 9)
        XCTAssertEqual(dashboard.todayUsage, 6)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func date(month: Int, day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2025, month: month, day: day, hour: hour))!
    }

    private func snapshot(day: Int, hour: Int, used: Double) -> UsageSnapshot {
        UsageSnapshot(collectedAt: date(day: day, hour: hour), limit: 100, used: used, remaining: 100 - used, remainingPercent: 100 - used, resetAt: "2026-01-13")
    }

    private func dayUsage(on day: Int, in dashboard: PaceDashboardModel) -> Double? {
        dashboard.days.first { utc.isDate($0.day, inSameDayAs: date(day: day, hour: 0)) }?.actualUsage
    }

    private func resetSnapshot(day: Int, hour: Int, used: Double) -> UsageSnapshot {
        UsageSnapshot(collectedAt: date(day: day, hour: hour), limit: 10_000, used: used, remaining: 10_000 - used, remainingPercent: 100 - used / 100, resetAt: "2026-01-06T17:00:00Z")
    }
}
