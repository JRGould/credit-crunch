import AppKit
import XCTest
@testable import CodexCreditsMenubar

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testClosingPreferencesHidesAndReusesItsWindow() {
        let delegate = AppDelegate(notificationCoordinator: UsageNotificationCoordinator(
            notifier: RecordingNotifier(),
            deduplicator: RecordingDeduplicator()
        ))
        let showPreferences = NSSelectorFromString("showPreferences")
        _ = delegate.perform(showPreferences)
        guard let window = NSApp.windows.first(where: { $0.delegate === delegate }) else {
            return XCTFail("Preferences window was not created")
        }

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(delegate.windowShouldClose(window))
        XCTAssertFalse(window.isVisible)

        _ = delegate.perform(showPreferences)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window === NSApp.windows.first(where: { $0.delegate === delegate }))
        window.delegate = nil
        window.close()
    }

    private final class RecordingNotifier: NotificationDelivering {
        func deliver(_ decision: UsageNotificationDecision) {}
    }

    private final class RecordingDeduplicator: NotificationDeduplicating {
        func contains(_ identifier: String) -> Bool { false }
        func insert(_ identifier: String) {}
    }
}
