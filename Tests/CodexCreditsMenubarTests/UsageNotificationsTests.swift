import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class UsageNotificationsTests: XCTestCase {
    func testNotifiesOnlyWhenRemainingPercentCrossesConfiguredThreshold() {
        let previous = snapshot(remaining: 25)
        let current = snapshot(remaining: 20)
        let decision = UsageNotificationPolicy.thresholdCrossing(previous: previous, current: current, threshold: 20)
        XCTAssertEqual(decision?.title, "Codex usage is running low")
        XCTAssertEqual(decision?.body, "Only 20% of your individual limit remains.")
        XCTAssertNil(UsageNotificationPolicy.thresholdCrossing(previous: current, current: snapshot(remaining: 15), threshold: 20))
    }

    func testDoesNotNotifyWhenUsageDataIsUnavailable() {
        let unavailable = UsageSnapshot(collectedAt: Date(), limit: nil, used: nil, remaining: nil, remainingPercent: nil, resetAt: nil)
        XCTAssertNil(UsageNotificationPolicy.thresholdCrossing(previous: nil, current: unavailable, threshold: 20))
    }

    func testNotifiesWhenDailyUsageCrossesConfiguredThreshold() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let decision = UsageNotificationPolicy.dailyThresholdCrossing(
            previousUsagePercent: 79,
            currentUsagePercent: 81,
            threshold: 80,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(decision?.title, "Daily Codex usage is approaching its target")
        XCTAssertEqual(decision?.body, "You have used 81% of today’s target.")
        XCTAssertNil(UsageNotificationPolicy.dailyThresholdCrossing(previousUsagePercent: 81, currentUsagePercent: 90, threshold: 80, now: now, calendar: calendar))
    }

    func testCoordinatorDeduplicatesUsingInjectedNotifierStoreAndClock() {
        let notifier = RecordingNotifier()
        let store = RecordingDeduplicator()
        let coordinator = UsageNotificationCoordinator(notifier: notifier, deduplicator: store, clock: { Date(timeIntervalSince1970: 0) })
        coordinator.consider(previous: snapshot(remaining: 30), current: snapshot(remaining: 20), threshold: 20)
        coordinator.consider(previous: snapshot(remaining: 30), current: snapshot(remaining: 20), threshold: 20)
        XCTAssertEqual(notifier.decisions.count, 1)
        XCTAssertEqual(store.identifiers.count, 1)
    }

    func testCoordinatorDeduplicatesDailyAlertsAndDeliversTests() {
        let notifier = RecordingNotifier()
        let store = RecordingDeduplicator()
        let coordinator = UsageNotificationCoordinator(notifier: notifier, deduplicator: store, clock: { Date(timeIntervalSince1970: 0) })
        coordinator.considerDaily(previousUsagePercent: 79, currentUsagePercent: 80, threshold: 80)
        coordinator.considerDaily(previousUsagePercent: 79, currentUsagePercent: 80, threshold: 80)
        coordinator.deliverTest(UsageNotificationDecision(identifier: "test", title: "Test", body: "Working"))
        XCTAssertEqual(notifier.decisions.map(\.title), ["Daily Codex usage is approaching its target", "Test"])
        XCTAssertEqual(store.identifiers.count, 1)
    }

    private func snapshot(remaining: Double) -> UsageSnapshot {
        UsageSnapshot(collectedAt: Date(), limit: 100, used: 100 - remaining, remaining: remaining, remainingPercent: remaining, resetAt: "reset-a")
    }

    private final class RecordingNotifier: NotificationDelivering {
        var decisions: [UsageNotificationDecision] = []
        func deliver(_ decision: UsageNotificationDecision) { decisions.append(decision) }
    }

    private final class RecordingDeduplicator: NotificationDeduplicating {
        var identifiers = Set<String>()
        func contains(_ identifier: String) -> Bool { identifiers.contains(identifier) }
        func insert(_ identifier: String) { identifiers.insert(identifier) }
    }
}
