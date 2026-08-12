import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class UsageHistoryTests: XCTestCase {
    func testSnapshotRoundTripStoresOnlyMinimizedFields() throws {
        let snapshot = makeSnapshot(hour: 1, used: 12, resetAt: "reset-a")
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("token"))
        XCTAssertFalse(text.contains("account"))
        XCTAssertFalse(text.contains("email"))
    }

    func testSnapshotReadsUnversionedSchemaZero() throws {
        let data = """
        {"collectedAt":0,"limit":100,"used":20,"remaining":80,"remainingPercent":80,"resetAt":"reset-a"}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 0)
        XCTAssertEqual(snapshot.used, 20)
    }

    func testStoreAtomicallyWritesReadsPrunesAndSetsPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = FileUsageHistoryStore(fileURL: file, retentionLimit: 2)

        try store.record(makeSnapshot(hour: 1, used: 1))
        try store.record(makeSnapshot(hour: 2, used: 2))
        try store.record(makeSnapshot(hour: 3, used: 3))

        XCTAssertEqual(try store.load().map(\.used), [2, 3])
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
        XCTAssertEqual(try store.lastSuccessfulRefresh(), makeDate(hour: 3))
    }

    func testStoreDiscardsCorruptCacheAndCanClear() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = FileUsageHistoryStore(fileURL: file)
        try Data("not json".utf8).write(to: file)

        XCTAssertEqual(try store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try store.record(makeSnapshot(hour: 1, used: 1))
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testStoreKeepsDailyBoundariesWhenFrequentRefreshesReachRetentionLimit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = FileUsageHistoryStore(fileURL: file, retentionLimit: 8)

        for day in 1...3 {
            for hour in 0...3 {
                try store.record(makeSnapshot(day: day, hour: hour, used: Double((day - 1) * 4 + hour + 1)))
            }
        }

        let retained = try store.load()
        XCTAssertEqual(retained.map(\.used), [1, 4, 5, 8, 9, 10, 11, 12])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSnapshot(hour: Int, used: Double, resetAt: String = "reset-a") -> UsageSnapshot {
        UsageSnapshot(collectedAt: makeDate(hour: hour), limit: 100, used: used, remaining: 100 - used, remainingPercent: 100 - used, resetAt: resetAt)
    }

    private func makeSnapshot(day: Int, hour: Int, used: Double) -> UsageSnapshot {
        UsageSnapshot(collectedAt: makeDate(day: day, hour: hour), limit: 100, used: used, remaining: 100 - used, remainingPercent: 100 - used, resetAt: "reset-a")
    }

    private func makeDate(hour: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3_600))
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval((day - 1) * 86_400 + hour * 3_600))
    }
}
