import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class ConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "ConfigurationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suiteName) }

    @MainActor
    func testValidatesPersistedRetentionThresholdAndSimulationSettings() {
        let settings = AppSettings(defaults: defaults)
        settings.historyRetentionLimit = 1
        settings.notificationThresholdPercent = 0
        XCTAssertEqual(settings.historyRetentionLimit, FileUsageHistoryStore.defaultRetentionLimit)
        XCTAssertEqual(settings.notificationThresholdPercent, 20)
        XCTAssertFalse(settings.analyticsBackfillCompleted)
        settings.analyticsBackfillCompleted = true
        XCTAssertTrue(settings.analyticsBackfillCompleted)
        XCTAssertFalse(settings.saveSimulation(duration: 2, restoreDelay: 1))
        XCTAssertTrue(settings.saveSimulation(duration: 45, restoreDelay: 0))
        XCTAssertEqual(settings.simulationDuration, 45)
        XCTAssertEqual(settings.simulationRestoreDelay, 0)
    }
}
