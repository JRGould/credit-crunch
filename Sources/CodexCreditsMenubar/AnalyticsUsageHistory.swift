import Foundation

/// A minimized daily total imported from the account analytics view. It is
/// intentionally separate from `UsageSnapshot`: analytics does not include a
/// billing-period balance, limit, or reset identity.
struct AnalyticsDailyUsage: Codable, Equatable, Sendable {
    let day: Date
    let credits: Double
}

enum AnalyticsUsageServiceError: LocalizedError {
    case unreadableAuth
    case invalidAuth
    case missingToken
    case endpoint
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unreadableAuth: return "Codex authentication is unavailable."
        case .invalidAuth: return "Codex authentication is invalid."
        case .missingToken: return "Codex authentication has no access token."
        case .endpoint: return "Usage analytics is unavailable."
        case .malformedResponse: return "Usage analytics could not be read."
        }
    }
}

struct AnalyticsUsageService {
    let authFileURL: URL
    let endpoint: URL
    let session: URLSession

    init(configuration: RequestConfiguration = RequestConfiguration(), session: URLSession = .shared) {
        self.authFileURL = configuration.authFileURL
        self.endpoint = configuration.usageURL
            .deletingLastPathComponent()
            .appendingPathComponent("analytics/daily-workspace-usage-counts")
        self.session = session
    }

    init(authFileURL: URL, endpoint: URL, session: URLSession = .shared) {
        self.authFileURL = authFileURL
        self.endpoint = endpoint
        self.session = session
    }

    func fetchDailyUsage(from start: Date, through end: Date, calendar: Calendar = .current) async throws -> [AnalyticsDailyUsage] {
        let auth = try loadAuth()
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AnalyticsUsageServiceError.endpoint
        }
        components.queryItems = [
            URLQueryItem(name: "start_date", value: Self.dayString(start, calendar: calendar)),
            URLQueryItem(name: "end_date", value: Self.dayString(end, calendar: calendar)),
            URLQueryItem(name: "group_by", value: "day"),
            URLQueryItem(name: "workspace_user", value: "true")
        ]
        guard let url = components.url else { throw AnalyticsUsageServiceError.endpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexCreditsMenubar", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnalyticsUsageServiceError.endpoint
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AnalyticsUsageServiceError.endpoint
        }
        return try Self.parseDailyUsage(data, calendar: calendar)
    }

    static func parseDailyUsage(_ data: Data, calendar: Calendar = .current) throws -> [AnalyticsDailyUsage] {
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            return try response.data.map { item in
                guard let day = dayDate(item.date, calendar: calendar), item.totals.credits >= 0 else {
                    throw AnalyticsUsageServiceError.malformedResponse
                }
                return AnalyticsDailyUsage(day: day, credits: item.totals.credits)
            }
        } catch let error as AnalyticsUsageServiceError {
            throw error
        } catch {
            throw AnalyticsUsageServiceError.malformedResponse
        }
    }

    private func loadAuth() throws -> AnalyticsAuthFile {
        guard let data = try? Data(contentsOf: authFileURL) else { throw AnalyticsUsageServiceError.unreadableAuth }
        guard let auth = try? JSONDecoder().decode(AnalyticsAuthFile.self, from: data) else { throw AnalyticsUsageServiceError.invalidAuth }
        guard !auth.accessToken.isEmpty else { throw AnalyticsUsageServiceError.missingToken }
        return auth
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func dayDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private struct Response: Decodable {
        let data: [DailyRecord]
    }

    private struct DailyRecord: Decodable {
        let date: String
        let totals: Totals
    }

    private struct Totals: Decodable {
        let credits: Double
    }
}

struct FileAnalyticsDailyUsageStore {
    static let retentionDays = 120

    let fileURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    init(
        fileURL: URL = Self.defaultFileURL(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func load() throws -> [AnalyticsDailyUsage] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try JSONDecoder().decode([AnalyticsDailyUsage].self, from: Data(contentsOf: fileURL))
                .sorted { $0.day < $1.day }
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return []
        }
    }

    func merge(_ dailyUsage: [AnalyticsDailyUsage]) throws {
        var byDay = Dictionary(try load().map {
            (calendar.startOfDay(for: $0.day), $0)
        }, uniquingKeysWith: { _, newest in newest })
        for usage in dailyUsage {
            let day = calendar.startOfDay(for: usage.day)
            byDay[day] = AnalyticsDailyUsage(day: day, credits: usage.credits)
        }
        let retained = byDay.values.sorted { $0.day < $1.day }.suffix(Self.retentionDays)
        try write(Array(retained))
    }

    private func write(_ dailyUsage: [AnalyticsDailyUsage]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(dailyUsage).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexCreditsMenubar", isDirectory: true)
            .appendingPathComponent("analytics-daily-usage.json", isDirectory: false)
    }
}

private struct AnalyticsAuthFile: Decodable {
    let accessToken: String
    let accountID: String?

    enum CodingKeys: String, CodingKey { case tokens }
    enum TokenKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessTokenCamel = "accessToken"
        case accountID = "account_id"
        case accountIDCamel = "accountId"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let tokens = try root.nestedContainer(keyedBy: TokenKeys.self, forKey: .tokens)
        accessToken = try tokens.decodeIfPresent(String.self, forKey: .accessToken)
            ?? tokens.decodeIfPresent(String.self, forKey: .accessTokenCamel) ?? ""
        accountID = try tokens.decodeIfPresent(String.self, forKey: .accountID)
            ?? tokens.decodeIfPresent(String.self, forKey: .accountIDCamel)
    }
}
