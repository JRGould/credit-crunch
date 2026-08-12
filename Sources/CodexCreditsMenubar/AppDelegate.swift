import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private var historyStore: FileUsageHistoryStore { FileUsageHistoryStore(retentionLimit: settings.historyRetentionLimit) }
    private let analyticsHistoryStore = FileAnalyticsDailyUsageStore()
    private let notificationCoordinator = UsageNotificationCoordinator(notifier: LocalUsageNotifier(), deduplicator: UserDefaultsNotificationDeduplicator())
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var lastUpdated: Date?
    private var latestSpendControl: SpendControl?
    private var refreshError: String?
    private var preferencesWindow: NSWindow?
    private var simulatedUsagePercent: Double?
    private var simulationTask: Task<Void, Never>?
    private var analyticsBackfillTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = UsageStatusIcon.make(usagePercent: nil)
        statusItem.button?.toolTip = "Codex usage loading"
        rebuildMenu()
        scheduleRefresh()
        refresh()
        backfillAnalyticsHistoryIfNeeded()
    }

    // This is an accessory app with no main window. Closing Preferences must
    // not be treated as closing the application itself.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        simulationTask?.cancel()
        analyticsBackfillTask?.cancel()
    }

    @objc private func refresh() {
        refreshError = nil
        rebuildMenu()
        Task {
            do {
                let data = try await UsageService().fetchSpendControl()
                latestSpendControl = data
                lastUpdated = Date()
                let snapshot = UsageSnapshot(spendControl: data, collectedAt: lastUpdated!)
                let previous = try? historyStore.load().last
                try? historyStore.record(snapshot)
                if settings.notificationsEnabled { notificationCoordinator.consider(previous: previous, current: snapshot, threshold: settings.notificationThresholdPercent) }
                refreshError = nil
            } catch {
                refreshError = error.localizedDescription
            }
            rebuildMenu()
        }
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(settings.refreshIntervalMinutes * 60), target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    private func backfillAnalyticsHistoryIfNeeded() {
        guard !settings.analyticsBackfillCompleted else { return }
        // Installations that already imported before this first-run marker was
        // introduced keep their local history without making another request.
        guard (try? analyticsHistoryStore.load().isEmpty) ?? true else {
            settings.analyticsBackfillCompleted = true
            return
        }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: end)?.start,
              let start = calendar.date(byAdding: .month, value: -1, to: currentMonthStart)
        else { return }
        analyticsBackfillTask = Task {
            defer { analyticsBackfillTask = nil }
            do {
                let dailyUsage = try await AnalyticsUsageService().fetchDailyUsage(from: start, through: end, calendar: calendar)
                try analyticsHistoryStore.merge(dailyUsage)
                settings.analyticsBackfillCompleted = true
            } catch {
                // Retry on a later launch; current spend-control refreshes remain independent.
            }
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let snapshots = (try? historyStore.load()) ?? []
        let importedDailyUsage = (try? analyticsHistoryStore.load()) ?? []
        let dashboard = latestSpendControl.map { _ in
            UsagePresentation.paceDashboard(snapshots: snapshots, importedDailyUsage: importedDailyUsage)
        }
        let usagePercent = simulatedUsagePercent ?? dashboard.flatMap(StatusIconPresentation.dailyTargetUsagePercent)
        statusItem.button?.title = ""
        statusItem.button?.image = UsageStatusIcon.make(usagePercent: usagePercent)
        statusItem.button?.toolTip = StatusIconPresentation.tooltip(
            dailyTargetUsagePercent: dashboard.flatMap(StatusIconPresentation.dailyTargetUsagePercent),
            simulatedBillingUsagePercent: simulatedUsagePercent
        )
        let menu = NSMenu()
        if let dashboard {
            let dashboardView = PaceDashboardView(model: dashboard)
            let dashboardItem = NSMenuItem()
            dashboardItem.view = dashboardView
            dashboardItem.setAccessibilityLabel(dashboardView.accessibilityLabel())
            menu.addItem(dashboardItem)
        } else {
            menu.addItem(withTitle: refreshError ?? "Loading spend-control usage…", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: lastUpdated.map { "Last update: \(Self.dateFormatter.string(from: $0))" } ?? "Last update: never", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CreditCrunch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func startUsageSimulation() {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            guard let self else { return }
            let stepCount = 60
            for step in 0...stepCount {
                guard !Task.isCancelled else { return }
                self.simulatedUsagePercent = UsageSimulation.usagePercent(elapsed: Double(step) * self.settings.simulationDuration / Double(stepCount), duration: self.settings.simulationDuration)
                self.rebuildMenu()
                if step < stepCount {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(self.settings.simulationRestoreDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.simulatedUsagePercent = nil
            self.rebuildMenu()
            self.refresh()
        }
    }

    @objc private func showPreferences() {
        if let preferencesWindow {
            NSApp.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }
        let popup = NSPopUpButton(frame: NSRect(x: 20, y: 48, width: 240, height: 28), pullsDown: false)
        let values = [5, 15, 30, 60]
        popup.addItems(withTitles: values.map { "Refresh every \($0) minutes" })
        popup.selectItem(at: values.firstIndex(of: settings.refreshIntervalMinutes) ?? 1)
        popup.target = self; popup.action = #selector(changeInterval(_:))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 470)); view.addSubview(popup)
        let note = NSTextField(labelWithString: "Credentials are read only when refreshing and are never stored.")
        note.frame = NSRect(x: 20, y: 18, width: 390, height: 20); note.font = .systemFont(ofSize: 11); view.addSubview(note)
        let notifications = NSButton(checkboxWithTitle: "Notify when remaining limit is low", target: self, action: #selector(changeNotifications(_:)))
        notifications.frame = NSRect(x: 20, y: 404, width: 350, height: 24); notifications.state = settings.notificationsEnabled ? .on : .off; view.addSubview(notifications)
        addLabel("Notification threshold (% remaining)", y: 362, to: view)
        addField(value: settings.notificationThresholdPercent, y: 357, tag: 1, to: view)
        addLabel("History retention (samples)", y: 318, to: view)
        addField(value: settings.historyRetentionLimit, y: 313, tag: 2, to: view)
        let clear = NSButton(title: "Clear Local History…", target: self, action: #selector(confirmClearHistory))
        clear.frame = NSRect(x: 20, y: 270, width: 180, height: 30); view.addSubview(clear)
        let debug = NSTextField(labelWithString: "Debug simulation")
        debug.frame = NSRect(x: 20, y: 224, width: 240, height: 22); debug.font = .boldSystemFont(ofSize: 13); view.addSubview(debug)
        addLabel("Duration (seconds)", y: 182, to: view)
        addField(value: Int(settings.simulationDuration), y: 177, tag: 3, to: view)
        addLabel("Restore delay (seconds)", y: 138, to: view)
        addField(value: Int(settings.simulationRestoreDelay), y: 133, tag: 4, to: view)
        let simulate = NSButton(title: "Run Simulation", target: self, action: #selector(startUsageSimulation))
        simulate.frame = NSRect(x: 20, y: 92, width: 150, height: 30); view.addSubview(simulate)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CreditCrunch Preferences"; window.contentView = view; window.delegate = self; window.center(); window.makeKeyAndOrderFront(nil)
        preferencesWindow = window
    }

    @objc private func changeInterval(_ sender: NSPopUpButton) {
        settings.refreshIntervalMinutes = [5, 15, 30, 60][max(0, sender.indexOfSelectedItem)]
        scheduleRefresh()
    }

    @objc private func changeNotifications(_ sender: NSButton) {
        settings.notificationsEnabled = sender.state == .on
        guard settings.notificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            if !granted { Task { @MainActor in self?.settings.notificationsEnabled = false } }
        }
    }

    @objc private func changeNumberSetting(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue) else { sender.stringValue = valueForField(sender.tag); return }
        switch sender.tag {
        case 1: settings.notificationThresholdPercent = value
        case 2: settings.historyRetentionLimit = value
        case 3, 4:
            let duration = sender.tag == 3 ? TimeInterval(value) : settings.simulationDuration
            let delay = sender.tag == 4 ? TimeInterval(value) : settings.simulationRestoreDelay
            guard settings.saveSimulation(duration: duration, restoreDelay: delay) else { sender.stringValue = valueForField(sender.tag); return }
        default: return
        }
        sender.stringValue = valueForField(sender.tag)
    }

    @objc private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear local usage history?"
        alert.informativeText = "This removes only CreditCrunch’s local usage cache. Your credentials are not affected."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? historyStore.clear()
        rebuildMenu()
    }

    private func addLabel(_ text: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 20, y: y, width: 275, height: 24)
        view.addSubview(label)
    }

    private func addField(value: Int, y: CGFloat, tag: Int, to view: NSView) {
        let field = NSTextField(string: String(value))
        field.frame = NSRect(x: 310, y: y, width: 90, height: 26)
        field.tag = tag; field.target = self; field.action = #selector(changeNumberSetting(_:))
        view.addSubview(field)
    }

    private func valueForField(_ tag: Int) -> String {
        switch tag {
        case 1: return String(settings.notificationThresholdPercent)
        case 2: return String(settings.historyRetentionLimit)
        case 3: return String(Int(settings.simulationDuration))
        case 4: return String(Int(settings.simulationRestoreDelay))
        default: return ""
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === preferencesWindow { preferencesWindow = nil }
    }

    private static let dateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter }()
}

enum StatusIconPresentation {
    static func dailyTargetUsagePercent(_ dashboard: PaceDashboardModel) -> Double? {
        guard let todayUsage = dashboard.todayUsage,
              let dailyTarget = dashboard.dailyTarget,
              todayUsage.isFinite,
              dailyTarget.isFinite,
              todayUsage >= 0,
              dailyTarget >= 0
        else { return nil }

        if dailyTarget == 0 { return todayUsage > 0 ? 100 : 0 }
        return min(max(todayUsage / dailyTarget * 100, 0), 100)
    }

    static func tooltip(dailyTargetUsagePercent: Double?, simulatedBillingUsagePercent: Double?) -> String {
        if let simulatedBillingUsagePercent {
            return "Simulated Codex billing usage: \(Int(simulatedBillingUsagePercent.rounded()))% used"
        }
        if let dailyTargetUsagePercent {
            return "Codex daily target: \(Int(dailyTargetUsagePercent.rounded()))% used today"
        }
        return "Codex daily target unavailable"
    }
}

@main
enum CodexCreditsMenubarApplication {
    @MainActor private static let delegate = AppDelegate()

    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}
