import Foundation

/// The intentionally small, on-disk representation of a successful usage refresh.
/// It never contains credentials, account information, or the server response.
struct UsageSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let collectedAt: Date
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let remainingPercent: Double?
    let resetAt: String?

    init(
        collectedAt: Date,
        limit: Double?,
        used: Double?,
        remaining: Double?,
        remainingPercent: Double?,
        resetAt: String?,
        schemaVersion: Int = UsageSnapshot.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.collectedAt = collectedAt
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }

    init(spendControl: SpendControl, collectedAt: Date = Date()) {
        self.init(
            collectedAt: collectedAt,
            limit: spendControl.limit,
            used: spendControl.used,
            remaining: spendControl.remaining,
            remainingPercent: spendControl.remainingPercent,
            resetAt: spendControl.resetAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, collectedAt, limit, used, remaining, remainingPercent, resetAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Version zero was the unversioned development representation.  Keeping this
        // migration makes old local files readable without widening their data shape.
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        collectedAt = try values.decode(Date.self, forKey: .collectedAt)
        limit = try values.decodeIfPresent(Double.self, forKey: .limit)
        used = try values.decodeIfPresent(Double.self, forKey: .used)
        remaining = try values.decodeIfPresent(Double.self, forKey: .remaining)
        remainingPercent = try values.decodeIfPresent(Double.self, forKey: .remainingPercent)
        resetAt = try values.decodeIfPresent(String.self, forKey: .resetAt)
    }
}

protocol UsageHistoryStore {
    func load() throws -> [UsageSnapshot]
    func record(_ snapshot: UsageSnapshot) throws
    func clear() throws
}

extension UsageHistoryStore {
    func lastSuccessfulRefresh() throws -> Date? {
        try load().map(\.collectedAt).max()
    }
}

/// A single app-owned cache file.  Corrupt files are discarded, so a bad local
/// cache can never prevent the next live refresh from succeeding.
struct FileUsageHistoryStore: UsageHistoryStore {
    static let defaultRetentionLimit = 1_000

    let fileURL: URL
    let retentionLimit: Int
    private let fileManager: FileManager

    init(
        fileURL: URL = Self.defaultFileURL(),
        retentionLimit: Int = Self.defaultRetentionLimit,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
        self.fileManager = fileManager
    }

    func load() throws -> [UsageSnapshot] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let snapshots = try JSONDecoder().decode([UsageSnapshot].self, from: Data(contentsOf: fileURL))
            return snapshots.sorted { $0.collectedAt < $1.collectedAt }
        } catch {
            // The cache is disposable; remove only this app-owned file and recover.
            try? fileManager.removeItem(at: fileURL)
            return []
        }
    }

    func record(_ snapshot: UsageSnapshot) throws {
        var snapshots = try load()
        snapshots.append(snapshot)
        snapshots.sort { $0.collectedAt < $1.collectedAt }
        if snapshots.count > retentionLimit {
            snapshots = compactedSnapshots(snapshots)
        }
        try write(snapshots)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func write(_ snapshots: [UsageSnapshot]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Keep each completed calendar day's opening and closing samples before
    /// falling back to a raw count limit.  Daily pacing needs those boundaries,
    /// while retaining every five-minute refresh would otherwise erase the
    /// preceding billing period within a few days.
    private func compactedSnapshots(_ snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        let byDay = Dictionary(grouping: snapshots) {
            Calendar.current.startOfDay(for: $0.collectedAt)
        }
        guard byDay.count > 1 else {
            return Array(snapshots.suffix(retentionLimit))
        }

        let boundaries = byDay.values.flatMap { daySnapshots -> [UsageSnapshot] in
            Dictionary(grouping: daySnapshots) { $0.resetAt ?? "unavailable" }
                .values
                .flatMap { periodSnapshots -> [UsageSnapshot] in
                    let ordered = periodSnapshots.sorted { $0.collectedAt < $1.collectedAt }
                    guard let first = ordered.first, let last = ordered.last else { return [] }
                    return first == last ? [first] : [first, last]
                }
        }
        .sorted { $0.collectedAt < $1.collectedAt }

        return boundaries.count <= retentionLimit
            ? boundaries
            : Array(boundaries.suffix(retentionLimit))
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("CodexCreditsMenubar", isDirectory: true)
            .appendingPathComponent("usage-history.json", isDirectory: false)
    }
}
