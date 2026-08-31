import AppKit
import UserNotifications
import XCTest
@testable import CodexCreditsMenubar

final class AppDelegateTests: XCTestCase {
    func testForegroundNotificationsArePresented() {
        XCTAssertTrue(foregroundNotificationPresentationOptions.contains(.banner))
        XCTAssertTrue(foregroundNotificationPresentationOptions.contains(.list))
        XCTAssertTrue(foregroundNotificationPresentationOptions.contains(.sound))
    }

    func testNotificationPreferencesRequireAuthorization() {
        XCTAssertTrue(notificationPreferencesAvailable(for: .authorized))
        XCTAssertTrue(notificationPreferencesAvailable(for: .provisional))
        XCTAssertFalse(notificationPreferencesAvailable(for: .notDetermined))
        XCTAssertFalse(notificationPreferencesAvailable(for: .denied))
    }

    @MainActor
    func testClosingPreferencesHidesAndReusesItsWindow() {
        let delegate = AppDelegate(notificationCoordinator: UsageNotificationCoordinator(
            notifier: RecordingNotifier(),
            deduplicator: RecordingDeduplicator()
        ))
        delegate.presentPreferences(notificationAuthorizationStatus: .authorized)
        guard let window = NSApp.windows.first(where: { $0.delegate === delegate }) else {
            return XCTFail("Preferences window was not created")
        }

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(delegate.windowShouldClose(window))
        XCTAssertFalse(window.isVisible)

        delegate.presentPreferences(notificationAuthorizationStatus: .authorized)
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
