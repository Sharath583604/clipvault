import Foundation

/// Preview masking and retention rules. Values come from Settings (shared defaults in the
/// app group), but the policy itself is a plain value so it is trivially testable.
public struct SensitivePolicy: Sendable, Equatable {
    /// Days to keep ordinary items. 0 means keep forever.
    public var retentionDays: Int
    /// Lifetime of OTP and card items.
    public var sensitiveTTL: TimeInterval
    public var maxPreviewLength: Int

    public init(retentionDays: Int = 30, sensitiveTTL: TimeInterval = 10 * 60,
                maxPreviewLength: Int = 200) {
        self.retentionDays = retentionDays
        self.sensitiveTTL = sensitiveTTL
        self.maxPreviewLength = maxPreviewLength
    }

    public func expiry(isSensitive: Bool, from now: Date) -> Date? {
        if isSensitive { return now.addingTimeInterval(sensitiveTTL) }
        guard retentionDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: retentionDays, to: now)
    }

    public func preview(for text: String, classification: Classification) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if classification.types.contains(.card) {
            let digits = trimmed.filter { $0.isNumber }
            return "•••• •••• •••• " + digits.suffix(4)
        }
        if classification.types.contains(.otp) {
            return String(repeating: "•", count: trimmed.filter { $0.isNumber }.count)
        }
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(maxPreviewLength))
    }
}
