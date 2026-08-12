import Foundation

enum UsageSimulation {
    static let defaultDuration: TimeInterval = 30
    static let defaultRestorationDelay: TimeInterval = 5
    static let durationRange: ClosedRange<TimeInterval> = 5...3_600
    static let restorationDelayRange: ClosedRange<TimeInterval> = 0...3_600

    static func isValid(duration: TimeInterval, restorationDelay: TimeInterval) -> Bool {
        durationRange.contains(duration) && restorationDelayRange.contains(restorationDelay)
    }

    static func usagePercent(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        min(100, max(0, elapsed / duration * 100))
    }

    static func usagePercent(elapsed: TimeInterval) -> Double {
        usagePercent(elapsed: elapsed, duration: defaultDuration)
    }
}
