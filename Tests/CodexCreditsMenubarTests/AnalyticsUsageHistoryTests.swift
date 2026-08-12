import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class AnalyticsUsageHistoryTests: XCTestCase {
    func testParsesOnlyDailyCredits() throws {
        let data = """
        {"data":[
          {"date":"2026-07-30","totals":{"credits":12,"threads":99},"clients":[{"client_id":"ignored"}]},
          {"date":"2026-07-31","totals":{"credits":18}}
        ],"group_by":"day"}
        """.data(using: .utf8)!

        XCTAssertEqual(
            try AnalyticsUsageService.parseDailyUsage(data, calendar: utc),
            [
                AnalyticsDailyUsage(day: date(day: 30), credits: 12),
                AnalyticsDailyUsage(day: date(day: 31), credits: 18)
            ]
        )
    }

    func testStoreMergesByDayBoundsHistoryAndUsesRestrictivePermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("analytics.json")
        let store = FileAnalyticsDailyUsageStore(fileURL: file, calendar: utc)

        try store.merge([
            AnalyticsDailyUsage(day: date(day: 1), credits: 1),
            AnalyticsDailyUsage(day: date(day: 2), credits: 2)
        ])
        try store.merge([AnalyticsDailyUsage(day: date(day: 2), credits: 3)])

        XCTAssertEqual(try store.load().map(\.credits), [1, 3])
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 7, day: day))!
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
