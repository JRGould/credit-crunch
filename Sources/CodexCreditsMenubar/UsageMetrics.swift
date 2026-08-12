import Foundation

enum UsageEstimateConfidence: Equatable {
    case unavailable
    case provisional
    case high
}

enum ProjectedExhaustionStatus: Equatable {
    case insufficientHistory
    case projected
    case noExhaustionWithinPeriod
    case afterReset
}

struct UsageMetrics: Equatable {
    let currentDayUsage: Double?
    let dailyBurnRate: Double?
    let projectedExhaustionDate: Date?
    let calendarDayBaseline: Double?
    let workdayIncrement: Double?
    let remainingCredits: Double?
    let calendarDaysUntilReset: Int?
    let workingDaysUntilReset: Int?
    /// Workday equivalents available through the reset time. Unlike the
    /// whole-day count, this includes a weekday reset day's 9am–5pm capacity.
    let workdayCapacityUntilReset: Double?
    let sustainableWorkdayIncrement: Double?
    let paceDelta: Double?
    let projectedResetBalance: Double?
    let estimateConfidence: UsageEstimateConfidence
    let projectedExhaustionStatus: ProjectedExhaustionStatus

    init(
        currentDayUsage: Double?,
        dailyBurnRate: Double?,
        projectedExhaustionDate: Date?,
        calendarDayBaseline: Double? = nil,
        workdayIncrement: Double? = nil,
        remainingCredits: Double? = nil,
        calendarDaysUntilReset: Int? = nil,
        workingDaysUntilReset: Int? = nil,
        workdayCapacityUntilReset: Double? = nil,
        sustainableWorkdayIncrement: Double? = nil,
        paceDelta: Double? = nil,
        projectedResetBalance: Double? = nil,
        estimateConfidence: UsageEstimateConfidence = .unavailable,
        projectedExhaustionStatus: ProjectedExhaustionStatus = .insufficientHistory
    ) {
        self.currentDayUsage = currentDayUsage
        self.dailyBurnRate = dailyBurnRate
        self.projectedExhaustionDate = projectedExhaustionDate
        self.calendarDayBaseline = calendarDayBaseline
        self.workdayIncrement = workdayIncrement
        self.remainingCredits = remainingCredits
        self.calendarDaysUntilReset = calendarDaysUntilReset
        self.workingDaysUntilReset = workingDaysUntilReset
        self.workdayCapacityUntilReset = workdayCapacityUntilReset
        self.sustainableWorkdayIncrement = sustainableWorkdayIncrement
        self.paceDelta = paceDelta
        self.projectedResetBalance = projectedResetBalance
        self.estimateConfidence = estimateConfidence
        self.projectedExhaustionStatus = projectedExhaustionStatus
    }
}

/// Conservative calculations over a single uninterrupted spend-control period.
/// Two completed daily intervals are high confidence. Sparse history falls back
/// to a clearly labelled provisional estimate only when reset budget math is
/// available.
enum UsageMetricsEngine {
    static func calculate(
        snapshots: [UsageSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageMetrics {
        let ordered = snapshots.sorted { $0.collectedAt < $1.collectedAt }
        guard let latest = ordered.last else { return UsageMetrics(currentDayUsage: nil, dailyBurnRate: nil, projectedExhaustionDate: nil) }

        let today = ordered.filter { calendar.isDate($0.collectedAt, inSameDayAs: now) && sameResetPeriod($0, latest) }
        let currentDayUsage = usageDelta(first: today.first, last: latest)
        let period = ordered.filter { sameResetPeriod($0, latest) }
        let forecast = paceForecast(period: period, latest: latest, now: now, calendar: calendar)
        let observedBurn = period.first.flatMap { burnRate(first: $0, last: latest) }
        let burn = observedBurn ?? (forecast.estimateConfidence == .provisional ? 0 : nil)
        let projectedDate = burn.flatMap { burn -> Date? in
            guard burn > 0, let remaining = forecast.remainingCredits else { return nil }
            let date = latest.collectedAt.addingTimeInterval((remaining / burn) * 86_400)
            guard forecast.resetDate.map({ date < $0 }) ?? true else { return nil }
            return date
        }
        let exhaustionStatus: ProjectedExhaustionStatus
        if projectedDate != nil {
            exhaustionStatus = .projected
        } else if let burn, burn == 0, forecast.resetDate != nil {
            exhaustionStatus = .noExhaustionWithinPeriod
        } else if observedBurn != nil, forecast.resetDate != nil {
            exhaustionStatus = .afterReset
        } else {
            exhaustionStatus = .insufficientHistory
        }
        return UsageMetrics(
            currentDayUsage: currentDayUsage,
            dailyBurnRate: burn,
            projectedExhaustionDate: projectedDate,
            calendarDayBaseline: forecast.calendarDayBaseline,
            workdayIncrement: forecast.workdayIncrement,
            remainingCredits: forecast.remainingCredits,
            calendarDaysUntilReset: forecast.calendarDaysUntilReset,
            workingDaysUntilReset: forecast.workingDaysUntilReset,
            workdayCapacityUntilReset: forecast.workdayCapacityUntilReset,
            sustainableWorkdayIncrement: forecast.sustainableWorkdayIncrement,
            paceDelta: forecast.paceDelta,
            projectedResetBalance: forecast.projectedResetBalance,
            estimateConfidence: burn == nil ? .unavailable : (forecast.estimateConfidence == .high ? .high : .provisional),
            projectedExhaustionStatus: exhaustionStatus
        )
    }

    private struct PaceForecast {
        let calendarDayBaseline: Double?
        let workdayIncrement: Double?
        let remainingCredits: Double?
        let calendarDaysUntilReset: Int?
        let workingDaysUntilReset: Int?
        let workdayCapacityUntilReset: Double?
        let sustainableWorkdayIncrement: Double?
        let paceDelta: Double?
        let projectedResetBalance: Double?
        let estimateConfidence: UsageEstimateConfidence
        let resetDate: Date?
    }

    private static func paceForecast(
        period: [UsageSnapshot],
        latest: UsageSnapshot,
        now: Date,
        calendar: Calendar
    ) -> PaceForecast {
        let remainingCredits = latest.remaining ?? remaining(limit: latest.limit, used: latest.used)
        let dayIncrements = completedDayIncrements(period, now: now, calendar: calendar)
        let highConfidence = dayIncrements.count >= 2
        let calendarDayBaseline = highConfidence ? robustMedian(dayIncrements.map(\.increment)) : nil
        let weekdayTotal = highConfidence ? robustMedian(dayIncrements.filter { isWorkday($0.day, calendar: calendar) }.map(\.increment)) : nil
        let workdayIncrement = weekdayTotal.flatMap { weekdayTotal in calendarDayBaseline.map { max(0, weekdayTotal - $0) } }
        guard let remainingCredits, remainingCredits >= 0,
              let resetAt = resetDate(latest.resetAt, calendar: calendar), resetAt > now
        else {
            return PaceForecast(calendarDayBaseline: calendarDayBaseline, workdayIncrement: workdayIncrement, remainingCredits: remainingCredits, calendarDaysUntilReset: nil, workingDaysUntilReset: nil, workdayCapacityUntilReset: nil, sustainableWorkdayIncrement: nil, paceDelta: nil, projectedResetBalance: nil, estimateConfidence: highConfidence ? .high : .unavailable, resetDate: nil)
        }

        guard let today = calendar.dateInterval(of: .day, for: now)?.start,
              let resetDay = calendar.dateInterval(of: .day, for: resetAt)?.start,
              let calendarDays = calendar.dateComponents([.day], from: today, to: resetDay).day,
              calendarDays >= 0
        else {
            return PaceForecast(calendarDayBaseline: calendarDayBaseline, workdayIncrement: workdayIncrement, remainingCredits: remainingCredits, calendarDaysUntilReset: nil, workingDaysUntilReset: nil, workdayCapacityUntilReset: nil, sustainableWorkdayIncrement: nil, paceDelta: nil, projectedResetBalance: nil, estimateConfidence: highConfidence ? .high : .unavailable, resetDate: resetAt)
        }

        let workingDays = workdays(from: today, until: resetDay, calendar: calendar)
        let workdayCapacity = Double(workingDays) + resetDayWorkdayCapacity(until: resetAt, calendar: calendar)
        let confidence: UsageEstimateConfidence = highConfidence ? .high : .provisional
        let fallbackBaseline = dayIncrements.first?.increment ?? 0
        let baseline = calendarDayBaseline ?? fallbackBaseline
        let increment = workdayIncrement ?? 0
        guard let calendarDayBaseline,
              let workdayIncrement,
              workdayCapacity > 0
        else {
            guard workdayCapacity > 0 else {
                return PaceForecast(calendarDayBaseline: calendarDayBaseline, workdayIncrement: workdayIncrement, remainingCredits: remainingCredits, calendarDaysUntilReset: calendarDays, workingDaysUntilReset: workingDays, workdayCapacityUntilReset: workdayCapacity, sustainableWorkdayIncrement: nil, paceDelta: nil, projectedResetBalance: nil, estimateConfidence: highConfidence ? .high : .unavailable, resetDate: resetAt)
            }
            let reservedBaseline = baseline * Double(calendarDays)
            let workdayBudget = remainingCredits - reservedBaseline
            let sustainable = workdayBudget > 0 ? workdayBudget / workdayCapacity : nil
            let paceDelta = sustainable.map { $0 - increment }
            let projectedBalance = sustainable.map { _ in remainingCredits - (reservedBaseline + increment * workdayCapacity) }
            return PaceForecast(calendarDayBaseline: baseline, workdayIncrement: increment, remainingCredits: remainingCredits, calendarDaysUntilReset: calendarDays, workingDaysUntilReset: workingDays, workdayCapacityUntilReset: workdayCapacity, sustainableWorkdayIncrement: sustainable, paceDelta: paceDelta, projectedResetBalance: projectedBalance, estimateConfidence: confidence, resetDate: resetAt)
        }

        let reservedBaseline = calendarDayBaseline * Double(calendarDays)
        let workdayBudget = remainingCredits - reservedBaseline
        guard workdayBudget > 0 else {
            return PaceForecast(calendarDayBaseline: calendarDayBaseline, workdayIncrement: workdayIncrement, remainingCredits: remainingCredits, calendarDaysUntilReset: calendarDays, workingDaysUntilReset: workingDays, workdayCapacityUntilReset: workdayCapacity, sustainableWorkdayIncrement: nil, paceDelta: nil, projectedResetBalance: nil, estimateConfidence: .high, resetDate: resetAt)
        }

        let sustainable = workdayBudget / workdayCapacity
        let paceDelta = sustainable - workdayIncrement
        let projectedBalance = remainingCredits - (reservedBaseline + workdayIncrement * workdayCapacity)
        return PaceForecast(calendarDayBaseline: calendarDayBaseline, workdayIncrement: workdayIncrement, remainingCredits: remainingCredits, calendarDaysUntilReset: calendarDays, workingDaysUntilReset: workingDays, workdayCapacityUntilReset: workdayCapacity, sustainableWorkdayIncrement: sustainable, paceDelta: paceDelta, projectedResetBalance: projectedBalance, estimateConfidence: .high, resetDate: resetAt)
    }

    /// Uses daily closing samples from completed calendar days only. This avoids
    /// treating a partial current day as a full day, while retaining all usage
    /// (including unattended automation) in the baseline.
    private static func completedDayIncrements(
        _ snapshots: [UsageSnapshot],
        now: Date,
        calendar: Calendar
    ) -> [(day: Date, increment: Double)] {
        guard let today = calendar.dateInterval(of: .day, for: now)?.start else { return [] }
        let closings = Dictionary(grouping: snapshots.compactMap { snapshot -> (Date, UsageSnapshot)? in
            guard snapshot.collectedAt < today, snapshot.used != nil,
                  let day = calendar.dateInterval(of: .day, for: snapshot.collectedAt)?.start
            else { return nil }
            return (day, snapshot)
        }, by: \.0).compactMap { day, snapshots in
            snapshots.max { $0.1.collectedAt < $1.1.collectedAt }.map { (day, $0.1) }
        }.sorted { $0.0 < $1.0 }

        return zip(closings, closings.dropFirst()).compactMap { previous, current in
            guard calendar.dateComponents([.day], from: previous.0, to: current.0).day == 1,
                  let increment = usageDelta(first: previous.1, last: current.1)
            else { return nil }
            return (current.0, increment)
        }
    }

    private static func robustMedian(_ values: [Double]) -> Double? {
        // Two completed intervals are the minimum evidence for a rate; median
        // keeps an unusually busy automation day from dominating the forecast.
        guard values.count >= 2 else { return nil }
        let ordered = values.sorted()
        let middle = ordered.count / 2
        return ordered.count.isMultiple(of: 2) ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle]
    }

    private static func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    private static func workdays(from start: Date, until end: Date, calendar: Calendar) -> Int {
        var count = 0
        var day = start
        while day < end {
            if isWorkday(day, calendar: calendar) { count += 1 }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return count
    }

    private static func resetDayWorkdayCapacity(until resetAt: Date, calendar: Calendar) -> Double {
        guard isWorkday(resetAt, calendar: calendar),
              let workdayStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: resetAt),
              let workdayEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: resetAt)
        else { return 0 }
        if resetAt <= workdayStart { return 0 }
        if resetAt >= workdayEnd { return 1 }
        return resetAt.timeIntervalSince(workdayStart) / workdayEnd.timeIntervalSince(workdayStart)
    }

    private static func resetDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        if let epoch = Double(value) { return Date(timeIntervalSince1970: epoch) }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))
    }

    private static func sameResetPeriod(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        guard let lhsReset = lhs.resetAt, let rhsReset = rhs.resetAt else { return false }
        return lhsReset == rhsReset
    }

    private static func usageDelta(first: UsageSnapshot?, last: UsageSnapshot) -> Double? {
        guard let first, let initial = first.used, let final = last.used, final >= initial else { return nil }
        return final - initial
    }

    private static func burnRate(first: UsageSnapshot, last: UsageSnapshot) -> Double? {
        guard last.collectedAt > first.collectedAt,
              let delta = usageDelta(first: first, last: last)
        else { return nil }
        return delta / last.collectedAt.timeIntervalSince(first.collectedAt) * 86_400
    }

    private static func remaining(limit: Double?, used: Double?) -> Double? {
        guard let limit, let used else { return nil }
        return limit - used
    }
}
