import Foundation

enum CreditFormatter {
    private static let wholeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    static func format(_ value: Double) -> String {
        guard abs(value) >= 1_000 else {
            return wholeNumberFormatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
        }

        let compact = (value / 1_000 * 10).rounded() / 10
        let text = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), compact)
        let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return "\(trimmed)k"
    }
}
