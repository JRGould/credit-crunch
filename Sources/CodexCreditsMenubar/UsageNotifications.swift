import Foundation
import UserNotifications

struct UsageNotificationDecision: Equatable {
    let identifier: String
    let title: String
    let body: String
}

enum UsageNotificationPolicy {
    static func thresholdCrossing(previous: UsageSnapshot?, current: UsageSnapshot, threshold: Int, now: Date = Date()) -> UsageNotificationDecision? {
        guard let remaining = current.remainingPercent,
              remaining <= Double(threshold),
              previous?.remainingPercent ?? 101 > Double(threshold)
        else { return nil }
        let period = current.resetAt ?? String(Int(now.timeIntervalSince1970 / 86_400))
        return UsageNotificationDecision(
            identifier: "remaining-threshold-\(threshold)-\(stableIdentifierComponent(period))",
            title: "Codex usage is running low",
            body: "Only \(Int(remaining.rounded()))% of your individual limit remains."
        )
    }

    private static func stableIdentifierComponent(_ value: String) -> String {
        value.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }.description
    }
}

protocol NotificationDelivering {
    func deliver(_ decision: UsageNotificationDecision)
}

protocol NotificationDeduplicating {
    func contains(_ identifier: String) -> Bool
    func insert(_ identifier: String)
}

final class UserDefaultsNotificationDeduplicator: NotificationDeduplicating {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func contains(_ identifier: String) -> Bool { defaults.bool(forKey: identifier) }
    func insert(_ identifier: String) { defaults.set(true, forKey: identifier) }
}

struct UsageNotificationCoordinator {
    let notifier: NotificationDelivering
    let deduplicator: NotificationDeduplicating
    let clock: () -> Date

    init(notifier: NotificationDelivering, deduplicator: NotificationDeduplicating, clock: @escaping () -> Date = Date.init) {
        self.notifier = notifier
        self.deduplicator = deduplicator
        self.clock = clock
    }

    func consider(previous: UsageSnapshot?, current: UsageSnapshot, threshold: Int) {
        guard let decision = UsageNotificationPolicy.thresholdCrossing(previous: previous, current: current, threshold: threshold, now: clock()),
              !deduplicator.contains(decision.identifier)
        else { return }
        deduplicator.insert(decision.identifier)
        notifier.deliver(decision)
    }
}

final class LocalUsageNotifier: NotificationDelivering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func deliver(_ decision: UsageNotificationDecision) {
        let content = UNMutableNotificationContent()
        content.title = decision.title
        content.body = decision.body
        center.add(UNNotificationRequest(identifier: decision.identifier, content: content, trigger: nil), withCompletionHandler: nil)
    }
}
