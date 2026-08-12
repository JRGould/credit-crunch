import Foundation

struct UsageResponse: Decodable {
    let spendControl: SpendControl?
    enum CodingKeys: String, CodingKey { case spendControl = "spend_control" }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spendControl = try values.decodeIfPresent(SpendControlEnvelope.self, forKey: .spendControl)?.individualLimit
    }

    private struct SpendControlEnvelope: Decodable {
        let individualLimit: SpendControl?

        enum CodingKeys: String, CodingKey { case individualLimit = "individual_limit" }
    }
}

struct SpendControl: Decodable, Equatable {
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let remainingPercent: Double?
    let resetAt: String?

    enum CodingKeys: String, CodingKey {
        case limit, monthlyLimit = "monthly_limit", used, usedCredits = "used_credits", creditsUsed = "credits_used"
        case remaining, remainingCredits = "remaining_credits", remainingPercent = "remaining_percent", remainingPercentCamel = "remainingPercent"
        case resetAt = "reset_at", resetsAt = "resets_at", resetAtCamel = "resetAt", resetsAtCamel = "resetsAt"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        limit = values.number(for: [.limit, .monthlyLimit])
        used = values.number(for: [.used, .usedCredits, .creditsUsed])
        remaining = values.number(for: [.remaining, .remainingCredits]) ?? Self.computedRemaining(limit: limit, used: used)
        remainingPercent = values.number(for: [.remainingPercent, .remainingPercentCamel]) ?? Self.computedRemainingPercent(limit: limit, used: used)
        resetAt = values.string(for: [.resetAt, .resetsAt, .resetAtCamel, .resetsAtCamel])
    }

    private static func computedRemaining(limit: Double?, used: Double?) -> Double? {
        guard let limit, let used else { return nil }; return limit - used
    }
    private static func computedRemainingPercent(limit: Double?, used: Double?) -> Double? {
        guard let limit, limit > 0, let used else { return nil }; return 100 - (used / limit * 100)
    }
}

private extension KeyedDecodingContainer where Key == SpendControl.CodingKeys {
    func number(for keys: [Key]) -> Double? {
        for key in keys {
            if let value = try? decode(Double.self, forKey: key) { return value }
            if let value = try? decode(Int.self, forKey: key) { return Double(value) }
            if let text = try? decode(String.self, forKey: key), let value = Double(text) { return value }
        }
        return nil
    }
    func string(for keys: [Key]) -> String? {
        for key in keys {
            if let value = try? decode(String.self, forKey: key) { return value }
            if let value = try? decode(Double.self, forKey: key) { return String(value) }
        }
        return nil
    }
}

extension SpendControl {
    var usagePercent: Double? {
        if let remainingPercent { return min(100, max(0, 100 - remainingPercent)) }
        guard let limit, limit > 0, let used else { return nil }
        return min(100, max(0, used / limit * 100))
    }

    var menuLines: [String] {
        [
            Self.line("Spend limit", limit), Self.line("Spent", used), Self.line("Remaining", remaining),
            remainingPercent.map { "Remaining: \(Self.formatPercent($0))%" }, resetAt.map { "Reset: \(Self.formatResetAt($0))" }
        ].compactMap { $0 }
    }

    private static func line(_ label: String, _ value: Double?) -> String? { value.map { "\(label): \(CreditFormatter.format($0))" } }
    private static func formatPercent(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }

    private static func formatResetAt(_ value: String) -> String {
        guard let epoch = Double(value) else { return value }
        return DateFormatter.localizedString(from: Date(timeIntervalSince1970: epoch), dateStyle: .medium, timeStyle: .short)
    }
}
