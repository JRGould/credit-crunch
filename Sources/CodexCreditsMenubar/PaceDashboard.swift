import AppKit

enum PaceDashboardStatus: Equatable {
    case underTarget
    case overTarget
    case unavailable
}

struct PaceDashboardDay: Equatable {
    let day: Date
    let actualUsage: Double?
}

struct PaceDashboardPeriodDay: Equatable {
    let day: Date
    let actualUsage: Double?
    let previousPeriodUsage: Double?
}

struct PaceDashboardProgress: Equatable {
    let fillFraction: Double?
    let usageText: String
    let targetText: String
    let statusText: String
}

struct PaceDashboardBillingPeriod: Equatable {
    let totalUsage: Double?
    let periodLimit: Double?
    let resetAt: Date?
    let usageText: String
    let resetText: String
    let days: [PaceDashboardPeriodDay]

    static let unavailable = PaceDashboardBillingPeriod(
        totalUsage: nil,
        periodLimit: nil,
        resetAt: nil,
        usageText: "Used  —",
        resetText: "Resets  unavailable",
        days: []
    )
}

struct PaceDashboardModel: Equatable {
    let status: PaceDashboardStatus
    let decision: String
    let remainingCredits: Double?
    let remainingWorkdays: Double?
    let todayUsage: Double?
    let dailyTarget: Double?
    let days: [PaceDashboardDay]
    let billingPeriod: PaceDashboardBillingPeriod

    init(
        status: PaceDashboardStatus,
        decision: String,
        remainingCredits: Double?,
        remainingWorkdays: Double?,
        todayUsage: Double?,
        dailyTarget: Double?,
        days: [PaceDashboardDay],
        billingPeriod: PaceDashboardBillingPeriod = .unavailable
    ) {
        self.status = status
        self.decision = decision
        self.remainingCredits = remainingCredits
        self.remainingWorkdays = remainingWorkdays
        self.todayUsage = todayUsage
        self.dailyTarget = dailyTarget
        self.days = days
        self.billingPeriod = billingPeriod
    }

    static func make(
        snapshots: [UsageSnapshot],
        importedDailyUsage: [AnalyticsDailyUsage] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> PaceDashboardModel {
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: now, calendar: calendar)
        let todayUsage = currentDayUsage(snapshots: snapshots, now: now, calendar: calendar)
        let liveBalanceTarget: Double? = metrics.remainingCredits.flatMap { remaining in
            guard let workdayCapacity = metrics.workdayCapacityUntilReset, workdayCapacity > 0 else { return nil }
            return max(0, remaining) / workdayCapacity
        }
        // On the reset day, allocating from the live balance makes the target
        // shrink as today's usage rises. Anchor it to the day's first balance
        // instead, so the remaining headroom tracks the spendable balance.
        let target: Double?
        if isActiveResetDay(snapshots: snapshots, now: now, calendar: calendar) {
            target = resetDayTarget(
                snapshots: snapshots,
                now: now,
                calendar: calendar,
                workdayCapacity: metrics.workdayCapacityUntilReset
            )
        } else {
            target = liveBalanceTarget
        }
        let status: PaceDashboardStatus
        let decision: String
        if let target, let todayUsage {
            if todayUsage > target {
                status = .overTarget
                decision = "\(CreditFormatter.format(todayUsage - target)) credits over target"
            } else {
                status = .underTarget
                decision = target == todayUsage ? "On target" : "\(CreditFormatter.format(target - todayUsage)) credits under target"
            }
        } else {
            status = .unavailable
            decision = snapshots.isEmpty ? "Waiting for usage data" : "Today's pace is not available yet"
        }

        let latest = snapshots.max { $0.collectedAt < $1.collectedAt }
        return PaceDashboardModel(
            status: status,
            decision: decision,
            remainingCredits: metrics.remainingCredits,
            remainingWorkdays: metrics.workdayCapacityUntilReset,
            todayUsage: todayUsage,
            dailyTarget: target,
            days: chartDays(snapshots: snapshots, importedDailyUsage: importedDailyUsage, now: now, calendar: calendar),
            billingPeriod: billingPeriod(latest: latest, snapshots: snapshots, importedDailyUsage: importedDailyUsage, now: now, calendar: calendar)
        )
    }

    var summary: String {
        [decision, remainingCredits.map { "\(CreditFormatter.format($0)) credits remaining" }, remainingWorkdays.map { "\(workdayCapacityText($0)) workdays until reset" }]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    var progress: PaceDashboardProgress {
        guard let todayUsage, let dailyTarget else {
            return PaceDashboardProgress(fillFraction: nil, usageText: "Usage unavailable", targetText: "Target unavailable", statusText: decision)
        }
        let fillFraction: Double
        if dailyTarget == 0 {
            fillFraction = todayUsage > 0 ? 1 : 0
        } else {
            fillFraction = min(max(todayUsage / dailyTarget, 0), 1)
        }
        return PaceDashboardProgress(
            fillFraction: fillFraction,
            usageText: "\(CreditFormatter.format(todayUsage)) used today",
            targetText: "of \(CreditFormatter.format(dailyTarget)) target",
            statusText: decision
        )
    }

    fileprivate func workdayCapacityText(_ capacity: Double) -> String {
        capacity.rounded() == capacity ? String(Int(capacity)) : String(format: "%.1f", capacity)
    }

    private static func billingPeriod(
        latest: UsageSnapshot?,
        snapshots: [UsageSnapshot],
        importedDailyUsage: [AnalyticsDailyUsage],
        now: Date,
        calendar: Calendar
    ) -> PaceDashboardBillingPeriod {
        let totalUsage = latest?.used
        let periodLimit = latest?.limit
        let resetAt = latest.flatMap { resetDate($0.resetAt, calendar: calendar) }
        let usageText: String
        if let totalUsage, let periodLimit {
            usageText = "Used  \(CreditFormatter.format(totalUsage)) of \(CreditFormatter.format(periodLimit))"
        } else if let totalUsage {
            usageText = "Used  \(CreditFormatter.format(totalUsage))"
        } else {
            usageText = "Used  —"
        }
        let resetText: String
        if let resetAt {
            resetText = "Resets  \(DateFormatter.localizedString(from: resetAt, dateStyle: .medium, timeStyle: .short))"
        } else {
            resetText = "Resets  unavailable"
        }
        return PaceDashboardBillingPeriod(
            totalUsage: totalUsage,
            periodLimit: periodLimit,
            resetAt: resetAt,
            usageText: usageText,
            resetText: resetText,
            days: periodDays(snapshots: snapshots, latest: latest, importedDailyUsage: importedDailyUsage, now: now, calendar: calendar)
        )
    }

    private enum PeriodIdentity: Hashable {
        case resetDay(Date)
        case raw(String)

        var resetDay: Date? {
            guard case let .resetDay(day) = self else { return nil }
            return day
        }
    }

    private static func periodIdentity(for snapshot: UsageSnapshot, calendar: Calendar) -> PeriodIdentity? {
        guard let resetAt = snapshot.resetAt else { return nil }
        if let reset = resetDate(resetAt, calendar: calendar) {
            return .resetDay(calendar.startOfDay(for: reset))
        }
        return .raw(resetAt)
    }

    private static func periodDays(
        snapshots: [UsageSnapshot],
        latest: UsageSnapshot?,
        importedDailyUsage: [AnalyticsDailyUsage],
        now: Date,
        calendar: Calendar
    ) -> [PaceDashboardPeriodDay] {
        guard let latest,
              let currentIdentity = periodIdentity(for: latest, calendar: calendar),
              let currentReset = resetDate(latest.resetAt, calendar: calendar),
              let resetDay = calendar.dateInterval(of: .day, for: currentReset)?.start
        else { return [] }

        let groupedPairs = Dictionary(grouping: snapshots.compactMap { snapshot -> (PeriodIdentity, UsageSnapshot)? in
            periodIdentity(for: snapshot, calendar: calendar).map { ($0, snapshot) }
        }, by: \.0)
        let grouped = groupedPairs.mapValues { $0.map(\.1) }
        guard let currentSnapshots = grouped[currentIdentity],
              let observedStart = currentSnapshots.map(\.collectedAt).compactMap({ calendar.dateInterval(of: .day, for: $0)?.start }).min()
        else { return [] }

        let previous = grouped
            .filter { $0.key != currentIdentity }
            .max { ($0.value.map(\.collectedAt).max() ?? .distantPast) < ($1.value.map(\.collectedAt).max() ?? .distantPast) }
        let start = inferredPeriodStart(observedStart: observedStart, prior: previous, resetDay: resetDay)
        let previousStart = previous.flatMap { prior -> Date? in
            let priorBefore = grouped
                .filter { $0.key != currentIdentity && $0.key != prior.key }
                .max { ($0.value.map(\.collectedAt).max() ?? .distantPast) < ($1.value.map(\.collectedAt).max() ?? .distantPast) }
            guard let priorObservedStart = prior.value.map(\.collectedAt).compactMap({ calendar.dateInterval(of: .day, for: $0)?.start }).min() else { return nil }
            let priorReset = (prior.key.resetDay ?? resetDay)
            return inferredPeriodStart(observedStart: priorObservedStart, prior: priorBefore, resetDay: priorReset)
        }

        let importedByDay = Dictionary(uniqueKeysWithValues: importedDailyUsage.map {
            (calendar.startOfDay(for: $0.day), $0.credits)
        })
        let importedPreviousStart = calendar.date(byAdding: .month, value: -1, to: start)
        var slots: [PaceDashboardPeriodDay] = []
        var day = start
        while day <= resetDay {
            let localActual = day > now ? nil : periodDayUsage(on: day, snapshots: currentSnapshots, allSnapshots: snapshots, identity: currentIdentity, now: now, calendar: calendar)
            let actual = localActual ?? (!calendar.isDate(day, inSameDayAs: now) && day < now ? importedByDay[calendar.startOfDay(for: day)] : nil)
            let previousUsage: Double?
            if let previous, let previousStart {
                previousUsage = alignedPreviousUsage(
                    for: day,
                    currentStart: start,
                    previous: previous,
                    previousStart: previousStart,
                    allSnapshots: snapshots,
                    now: now,
                    calendar: calendar
                )
            } else {
                previousUsage = nil
            }
            let fallbackPreviousUsage = importedPreviousStart.flatMap { importedPreviousStart in
                importedAlignedUsage(for: day, currentStart: start, previousStart: importedPreviousStart, usageByDay: importedByDay, calendar: calendar)
            }
            slots.append(PaceDashboardPeriodDay(day: day, actualUsage: actual, previousPeriodUsage: previousUsage ?? fallbackPreviousUsage))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return slots
    }

    private static func inferredPeriodStart(
        observedStart: Date,
        prior: (key: PeriodIdentity, value: [UsageSnapshot])?,
        resetDay: Date
    ) -> Date {
        if case let .resetDay(previousReset)? = prior?.key, previousReset <= resetDay {
            return previousReset
        }
        return observedStart
    }

    private static func alignedPreviousUsage(
        for day: Date,
        currentStart: Date,
        previous: (key: PeriodIdentity, value: [UsageSnapshot]),
        previousStart: Date,
        allSnapshots: [UsageSnapshot],
        now: Date,
        calendar: Calendar
    ) -> Double? {
        let weekday = calendar.component(.weekday, from: day)
        let occurrence = weekdayOccurrence(of: day, from: currentStart, calendar: calendar)
        guard let previousDay = weekdayOccurrenceDay(weekday: weekday, occurrence: occurrence, from: previousStart, calendar: calendar) else { return nil }
        return periodDayUsage(on: previousDay, snapshots: previous.value, allSnapshots: allSnapshots, identity: previous.key, now: now, calendar: calendar)
    }

    private static func importedAlignedUsage(
        for day: Date,
        currentStart: Date,
        previousStart: Date,
        usageByDay: [Date: Double],
        calendar: Calendar
    ) -> Double? {
        let weekday = calendar.component(.weekday, from: day)
        let occurrence = weekdayOccurrence(of: day, from: currentStart, calendar: calendar)
        guard let previousDay = weekdayOccurrenceDay(weekday: weekday, occurrence: occurrence, from: previousStart, calendar: calendar) else { return nil }
        return usageByDay[calendar.startOfDay(for: previousDay)]
    }

    private static func weekdayOccurrence(of day: Date, from start: Date, calendar: Calendar) -> Int {
        var occurrence = 0
        var cursor = start
        while cursor <= day {
            if calendar.component(.weekday, from: cursor) == calendar.component(.weekday, from: day) {
                occurrence += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return occurrence
    }

    private static func weekdayOccurrenceDay(weekday: Int, occurrence: Int, from start: Date, calendar: Calendar) -> Date? {
        var matched = 0
        var cursor = start
        // A billing period is at most a month; this is a bounded lookup, even with sparse history.
        for _ in 0..<31 {
            if calendar.component(.weekday, from: cursor) == weekday {
                matched += 1
                if matched == occurrence { return cursor }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    private static func periodDayUsage(
        on day: Date,
        snapshots: [UsageSnapshot],
        allSnapshots: [UsageSnapshot],
        identity: PeriodIdentity,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        let samples = snapshots
            .filter { calendar.isDate($0.collectedAt, inSameDayAs: day) && periodIdentity(for: $0, calendar: calendar) == identity }
            .sorted { $0.collectedAt < $1.collectedAt }
        guard let close = samples.last else { return nil }
        // A reset can split today into two periods. Its post-reset samples are
        // still a safe partial-day reading because their delta never crosses
        // the boundary; historical mixed days stay unavailable below.
        if calendar.isDate(day, inSameDayAs: now) {
            return samples.count >= 2 ? usageDelta(first: samples.first, last: close) : nil
        }
        guard isUnmixedPeriodDay(day, identity: identity, snapshots: allSnapshots, calendar: calendar) else { return nil }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        guard isUnmixedPeriodDay(previousDay, identity: identity, snapshots: allSnapshots, calendar: calendar) else { return nil }
        let previous = snapshots
            .filter { calendar.isDate($0.collectedAt, inSameDayAs: previousDay) && periodIdentity(for: $0, calendar: calendar) == identity }
            .sorted { $0.collectedAt < $1.collectedAt }
        return usageDelta(first: previous.last, last: close)
    }

    private static func isUnmixedPeriodDay(_ day: Date, identity: PeriodIdentity, snapshots: [UsageSnapshot], calendar: Calendar) -> Bool {
        let identities = Set(snapshots.filter { calendar.isDate($0.collectedAt, inSameDayAs: day) }.compactMap { periodIdentity(for: $0, calendar: calendar) })
        return identities == [identity]
    }

    private static func chartDays(
        snapshots: [UsageSnapshot],
        importedDailyUsage: [AnalyticsDailyUsage],
        now: Date,
        calendar: Calendar
    ) -> [PaceDashboardDay] {
        guard let today = calendar.dateInterval(of: .day, for: now)?.start else { return [] }
        let importedByDay = Dictionary(uniqueKeysWithValues: importedDailyUsage.map {
            (calendar.startOfDay(for: $0.day), $0.credits)
        })
        guard let latest = snapshots.max(by: { $0.collectedAt < $1.collectedAt }),
              let latestIdentity = periodIdentity(for: latest, calendar: calendar)
        else { return (-6...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { PaceDashboardDay(day: $0, actualUsage: nil) }
        } }
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let actual: Double?
            if calendar.isDate(day, inSameDayAs: today) {
                let samples = snapshots
                    .filter { periodIdentity(for: $0, calendar: calendar) == latestIdentity && calendar.isDate($0.collectedAt, inSameDayAs: day) }
                    .sorted { $0.collectedAt < $1.collectedAt }
                actual = samples.count >= 2 ? usageDelta(first: samples.first, last: samples.last) : nil
            } else {
                let samples = snapshots
                    .filter { calendar.isDate($0.collectedAt, inSameDayAs: day) }
                    .sorted { $0.collectedAt < $1.collectedAt }
                if let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
                   let close = samples.last,
                   let identity = periodIdentity(for: close, calendar: calendar),
                   samples.allSatisfy({ periodIdentity(for: $0, calendar: calendar) == identity }) {
                    let previousDaySamples = snapshots
                        .filter { calendar.isDate($0.collectedAt, inSameDayAs: previousDay) }
                        .sorted { $0.collectedAt < $1.collectedAt }
                    actual = previousDaySamples.allSatisfy({ periodIdentity(for: $0, calendar: calendar) == identity })
                        ? usageDelta(first: previousDaySamples.last, last: close)
                        : nil
                } else {
                    actual = nil
                }
            }
            let fallback = calendar.isDate(day, inSameDayAs: today) ? nil : importedByDay[calendar.startOfDay(for: day)]
            return PaceDashboardDay(day: day, actualUsage: actual ?? fallback)
        }
    }

    private static func currentDayUsage(snapshots: [UsageSnapshot], now: Date, calendar: Calendar) -> Double? {
        let latest = snapshots.max { $0.collectedAt < $1.collectedAt }
        guard let latest, let latestIdentity = periodIdentity(for: latest, calendar: calendar) else { return nil }
        let today = snapshots
            .filter { periodIdentity(for: $0, calendar: calendar) == latestIdentity && calendar.isDate($0.collectedAt, inSameDayAs: now) }
            .sorted { $0.collectedAt < $1.collectedAt }
        guard today.count >= 2 else { return nil }
        return usageDelta(first: today.first, last: today.last)
    }

    private static func resetDayTarget(
        snapshots: [UsageSnapshot],
        now: Date,
        calendar: Calendar,
        workdayCapacity: Double?
    ) -> Double? {
        guard let latest = snapshots.max(by: { $0.collectedAt < $1.collectedAt }),
              let latestIdentity = periodIdentity(for: latest, calendar: calendar),
              isActiveResetDay(snapshots: snapshots, now: now, calendar: calendar),
              let workdayCapacity,
              workdayCapacity > 0
        else { return nil }

        let today = snapshots
            .filter { periodIdentity(for: $0, calendar: calendar) == latestIdentity && calendar.isDate($0.collectedAt, inSameDayAs: now) }
            .sorted { $0.collectedAt < $1.collectedAt }
        guard today.count >= 2,
              let first = today.first,
              let startingBalance = first.remaining ?? balance(limit: first.limit, used: first.used),
              startingBalance >= 0
        else { return nil }
        return startingBalance / workdayCapacity
    }

    private static func isActiveResetDay(snapshots: [UsageSnapshot], now: Date, calendar: Calendar) -> Bool {
        guard let latest = snapshots.max(by: { $0.collectedAt < $1.collectedAt }),
              let resetAt = resetDate(latest.resetAt, calendar: calendar)
        else { return false }
        return resetAt > now && calendar.isDate(resetAt, inSameDayAs: now)
    }

    private static func balance(limit: Double?, used: Double?) -> Double? {
        guard let limit, let used else { return nil }
        return limit - used
    }

    private static func resetDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        if let epoch = Double(value) { return Date(timeIntervalSince1970: epoch) }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))
    }

    private static func usageDelta(first: UsageSnapshot?, last: UsageSnapshot?) -> Double? {
        guard let first, let last, let initial = first.used, let final = last.used, final >= initial else { return nil }
        return final - initial
    }
}

final class PaceDashboardView: NSView {
    private let model: PaceDashboardModel
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        return formatter
    }()

    init(model: PaceDashboardModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 380))
        setAccessibilityLabel(model.summary)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 360, height: 380) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 16, dy: 14)
        drawPacing(in: bounds)
        let facts = [
            "Remaining  \(model.remainingCredits.map(CreditFormatter.format) ?? "—")",
            "Workdays  \(model.remainingWorkdays.map(model.workdayCapacityText) ?? "—")",
            "Today  \(model.todayUsage.map(CreditFormatter.format) ?? "—")",
            "On target  \(model.dailyTarget.map(CreditFormatter.format) ?? "—")"
        ]
        let factTop = bounds.maxY - 102
        for (index, fact) in facts.enumerated() {
            let column = index % 2
            let row = index / 2
            let rect = NSRect(x: bounds.minX + CGFloat(column) * 164, y: factTop - CGFloat(row) * 24, width: 156, height: 20)
            drawText(fact, in: rect, font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
        }

        let chart = NSRect(x: bounds.minX, y: bounds.minY + 120, width: bounds.width, height: 92)
        drawChart(in: chart)

        drawText("Billing period", in: NSRect(x: bounds.minX, y: bounds.minY + 94, width: 100, height: 16), font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
        drawText(model.billingPeriod.usageText, in: NSRect(x: bounds.minX + 100, y: bounds.minY + 94, width: bounds.width - 100, height: 16), font: .systemFont(ofSize: 11), color: .secondaryLabelColor, alignment: .right)
        drawPeriodStrip(in: NSRect(x: bounds.minX, y: bounds.minY + 18, width: bounds.width, height: 66))
    }

    private func drawPacing(in bounds: NSRect) {
        let progress = model.progress
        drawText("Today's pacing", in: NSRect(x: bounds.minX, y: bounds.maxY - 24, width: 150, height: 20), font: .boldSystemFont(ofSize: 15), color: .labelColor)
        drawText(progress.statusText, in: NSRect(x: bounds.minX + 150, y: bounds.maxY - 23, width: bounds.width - 150, height: 18), font: .systemFont(ofSize: 11, weight: .medium), color: statusColor, alignment: .right)

        let barRect = NSRect(x: bounds.minX, y: bounds.maxY - 47, width: bounds.width, height: 10)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()
        if let fillFraction = progress.fillFraction, fillFraction > 0 {
            let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: max(2, barRect.width * CGFloat(fillFraction)), height: barRect.height)
            statusColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 5, yRadius: 5).fill()
        }
        drawText(progress.usageText, in: NSRect(x: bounds.minX, y: bounds.maxY - 69, width: bounds.width / 2, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
        drawText(progress.targetText, in: NSRect(x: bounds.midX, y: bounds.maxY - 69, width: bounds.width / 2, height: 18), font: .systemFont(ofSize: 12), color: .secondaryLabelColor, alignment: .right)
    }

    private var statusColor: NSColor {
        switch model.status {
        case .overTarget: return .systemRed
        case .underTarget: return .systemGreen
        case .unavailable: return .secondaryLabelColor
        }
    }

    private func drawChart(in rect: NSRect) {
        drawText("Last 7 days", in: NSRect(x: rect.minX, y: rect.maxY - 16, width: 120, height: 16), font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
        if let target = model.dailyTarget {
            drawText("On target \(CreditFormatter.format(target))", in: NSRect(x: rect.maxX - 118, y: rect.maxY - 16, width: 118, height: 16), font: .systemFont(ofSize: 11), color: .secondaryLabelColor, alignment: .right)
        } else {
            drawText("On target unavailable", in: NSRect(x: rect.maxX - 135, y: rect.maxY - 16, width: 135, height: 16), font: .systemFont(ofSize: 11), color: .secondaryLabelColor, alignment: .right)
        }

        let plot = NSRect(x: rect.minX, y: rect.minY + 18, width: rect.width, height: rect.height - 42)
        NSColor.separatorColor.setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: plot.minX, y: plot.minY))
        baseline.line(to: NSPoint(x: plot.maxX, y: plot.minY))
        baseline.stroke()

        let maximum = max(model.dailyTarget ?? 0, model.days.compactMap(\.actualUsage).max() ?? 0, 1)
        if let target = model.dailyTarget {
            let y = plot.minY + plot.height * CGFloat(target / maximum)
            let path = NSBezierPath()
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }

        let step = plot.width / CGFloat(max(model.days.count, 1))
        for (index, day) in model.days.enumerated() {
            let x = plot.minX + CGFloat(index) * step + 5
            let width = max(8, step - 10)
            if let actual = day.actualUsage {
                let height = max(2, plot.height * CGFloat(actual / maximum))
                let bar = NSBezierPath(roundedRect: NSRect(x: x, y: plot.minY, width: width, height: height), xRadius: 3, yRadius: 3)
                (model.status == .overTarget ? NSColor.systemOrange : NSColor.controlAccentColor).setFill()
                bar.fill()
            }
            drawText(Self.dayFormatter.string(from: day.day), in: NSRect(x: x - 5, y: rect.minY, width: width + 10, height: 14), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor, alignment: .center)
        }
    }

    private func drawPeriodStrip(in rect: NSRect) {
        guard !model.billingPeriod.days.isEmpty else {
            drawText("Daily period usage unavailable", in: rect, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
            return
        }
        let days = model.billingPeriod.days
        let maximum = max(days.compactMap(\.actualUsage).max() ?? 0, days.compactMap(\.previousPeriodUsage).max() ?? 0, 1)
        let plot = NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: rect.height - 20)
        let step = plot.width / CGFloat(days.count)
        let baseline = plot.minY
        for (index, day) in days.enumerated() {
            let x = plot.minX + CGFloat(index) * step
            let width = max(2, step - 1)
            if let previous = day.previousPeriodUsage {
                let height = max(2, plot.height * 0.72 * CGFloat(previous / maximum))
                NSColor.secondaryLabelColor.withAlphaComponent(0.42).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: baseline, width: width, height: height), xRadius: 1, yRadius: 1).fill()
            }
            if let actual = day.actualUsage {
                let height = max(3, plot.height * CGFloat(actual / maximum))
                let currentWidth = max(2, width * 0.62)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: x + (width - currentWidth) / 2, y: baseline, width: currentWidth, height: height), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        drawText("Daily usage · muted: prior", in: NSRect(x: rect.minX, y: rect.maxY - 13, width: rect.width / 2, height: 13), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)
        let resetText = model.billingPeriod.resetAt.map {
            "Reset \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short))"
        } ?? "Reset unavailable"
        drawText(resetText, in: NSRect(x: rect.midX, y: rect.maxY - 13, width: rect.width / 2, height: 13), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor, alignment: .right)
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]).draw(in: rect)
    }
}
