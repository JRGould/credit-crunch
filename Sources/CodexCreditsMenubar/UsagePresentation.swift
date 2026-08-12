import Foundation

enum UsagePresentation {
    static func paceDashboard(
        snapshots: [UsageSnapshot],
        importedDailyUsage: [AnalyticsDailyUsage] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PaceDashboardModel {
        PaceDashboardModel.make(snapshots: snapshots, importedDailyUsage: importedDailyUsage, now: now, calendar: calendar)
    }

    static func metricLines(snapshots: [UsageSnapshot], now: Date = Date()) -> [String] {
        let metrics = UsageMetricsEngine.calculate(snapshots: snapshots, now: now)
        guard !snapshots.isEmpty else { return ["History: no local samples yet"] }
        var lines = ["Today used: \(number(metrics.currentDayUsage))"]
        lines.append(estimated("Daily burn: \(number(metrics.dailyBurnRate))", metrics: metrics))
        if let date = metrics.projectedExhaustionDate {
            lines.append(estimated("Projected exhaustion: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))", metrics: metrics))
        } else {
            lines.append(estimated(exhaustionLine(metrics.projectedExhaustionStatus), metrics: metrics))
        }
        lines.append("Remaining credits: \(number(metrics.remainingCredits))")
        lines.append(estimated("Calendar baseline: \(rate(metrics.calendarDayBaseline, unit: "day"))", metrics: metrics))
        lines.append(estimated("Workday pace: \(rate(metrics.workdayIncrement, unit: "workday"))", metrics: metrics))
        lines.append(daysLeft(calendarDays: metrics.calendarDaysUntilReset, workdays: metrics.workingDaysUntilReset))
        lines.append(estimated("Sustainable workday pace: \(rate(metrics.sustainableWorkdayIncrement, unit: "workday"))", metrics: metrics))
        lines.append(estimated(paceLine(metrics.paceDelta), metrics: metrics))
        lines.append(estimated("Projected reset balance: \(number(metrics.projectedResetBalance))", metrics: metrics))
        return lines
    }

    static func historyLines(snapshots: [UsageSnapshot], limit: Int = 5) -> [String] {
        guard !snapshots.isEmpty else { return ["Recent history: no local samples yet"] }
        return snapshots.sorted { $0.collectedAt > $1.collectedAt }.prefix(limit).map { snapshot in
            let used = number(snapshot.used)
            let remaining = snapshot.remainingPercent.map { "\(percent($0))% remaining" } ?? "remaining unavailable"
            return "\(DateFormatter.localizedString(from: snapshot.collectedAt, dateStyle: .none, timeStyle: .short)): \(used) used, \(remaining)"
        }
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "insufficient history" }
        return CreditFormatter.format(value)
    }

    private static func percent(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func rate(_ value: Double?, unit: String) -> String {
        guard let value else { return "unavailable" }
        return "\(number(value))/\(unit)"
    }

    private static func daysLeft(calendarDays: Int?, workdays: Int?) -> String {
        guard let calendarDays, let workdays else { return "Days left: unavailable" }
        return "Days left: \(calendarDays) calendar, \(workdays) workdays"
    }

    private static func paceLine(_ delta: Double?) -> String {
        guard let delta else { return "Pace: unavailable" }
        if abs(delta) < 0.01 { return "Pace: on pace" }
        if delta > 0 { return "Pace: pull back by \(number(delta))/workday" }
        return "Pace: can increase by \(number(-delta))/workday"
    }

    private static func exhaustionLine(_ status: ProjectedExhaustionStatus) -> String {
        switch status {
        case .projected:
            return "Projected exhaustion: insufficient history"
        case .noExhaustionWithinPeriod:
            return "Projected exhaustion: no exhaustion within period"
        case .afterReset:
            return "Projected exhaustion: after reset"
        case .insufficientHistory:
            return "Projected exhaustion: insufficient history"
        }
    }

    private static func estimated(_ line: String, metrics: UsageMetrics) -> String {
        metrics.estimateConfidence == .provisional ? "\(line) ⚠︎ low confidence" : line
    }
}
