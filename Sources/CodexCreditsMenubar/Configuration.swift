import Foundation

struct RequestConfiguration: Equatable {
    let authFileURL: URL
    let usageURL: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let authPath = environment["CODEX_AUTH_FILE"] ?? homeDirectory.appendingPathComponent(".codex/auth.json").path
        authFileURL = URL(fileURLWithPath: (authPath as NSString).expandingTildeInPath)

        let base = (environment["CODEX_CHATGPT_BASE_URL"] ?? "https://chatgpt.com/backend-api")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        usageURL = URL(string: "\(base)/wham/usage")!
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let refreshIntervalKey = "refreshIntervalMinutes"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let cacheEnabledKey = "cacheEnabled"
    static let historyRetentionLimitKey = "historyRetentionLimit"
    static let notificationThresholdKey = "notificationThresholdPercent"
    static let simulationDurationKey = "simulationDurationSeconds"
    static let simulationRestoreDelayKey = "simulationRestoreDelaySeconds"
    static let analyticsBackfillCompletedKey = "analyticsBackfillCompleted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.refreshIntervalKey) == nil {
            defaults.set(15, forKey: Self.refreshIntervalKey)
        }
    }

    var refreshIntervalMinutes: Int {
        get { max(1, defaults.integer(forKey: Self.refreshIntervalKey)) }
        set { defaults.set(max(1, newValue), forKey: Self.refreshIntervalKey) }
    }

    // Reserved persisted settings. Notifications and response caching are deliberately not enabled yet.
    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Self.notificationsEnabledKey) }
        set { defaults.set(newValue, forKey: Self.notificationsEnabledKey) }
    }

    var cacheEnabled: Bool {
        get { defaults.bool(forKey: Self.cacheEnabledKey) }
        set { defaults.set(newValue, forKey: Self.cacheEnabledKey) }
    }

    var historyRetentionLimit: Int {
        get { validated(defaults.integer(forKey: Self.historyRetentionLimitKey), fallback: FileUsageHistoryStore.defaultRetentionLimit, range: 10...10_000) }
        set { defaults.set(validated(newValue, fallback: FileUsageHistoryStore.defaultRetentionLimit, range: 10...10_000), forKey: Self.historyRetentionLimitKey) }
    }

    var analyticsBackfillCompleted: Bool {
        get { defaults.bool(forKey: Self.analyticsBackfillCompletedKey) }
        set { defaults.set(newValue, forKey: Self.analyticsBackfillCompletedKey) }
    }

    var notificationThresholdPercent: Int {
        get { validated(defaults.integer(forKey: Self.notificationThresholdKey), fallback: 20, range: 1...99) }
        set { defaults.set(validated(newValue, fallback: 20, range: 1...99), forKey: Self.notificationThresholdKey) }
    }

    var simulationDuration: TimeInterval {
        get { validatedDuration(defaults.double(forKey: Self.simulationDurationKey)) }
        set { defaults.set(validatedDuration(newValue), forKey: Self.simulationDurationKey) }
    }

    var simulationRestoreDelay: TimeInterval {
        get { validatedRestoreDelay(defaults.double(forKey: Self.simulationRestoreDelayKey)) }
        set { defaults.set(validatedRestoreDelay(newValue), forKey: Self.simulationRestoreDelayKey) }
    }

    @discardableResult
    func saveSimulation(duration: TimeInterval, restoreDelay: TimeInterval) -> Bool {
        guard UsageSimulation.isValid(duration: duration, restorationDelay: restoreDelay) else { return false }
        simulationDuration = duration
        simulationRestoreDelay = restoreDelay
        return true
    }

    private func validated(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        range.contains(value) ? value : fallback
    }

    private func validatedDuration(_ value: TimeInterval) -> TimeInterval { UsageSimulation.durationRange.contains(value) ? value : UsageSimulation.defaultDuration }
    private func validatedRestoreDelay(_ value: TimeInterval) -> TimeInterval { UsageSimulation.restorationDelayRange.contains(value) ? value : UsageSimulation.defaultRestorationDelay }
}
