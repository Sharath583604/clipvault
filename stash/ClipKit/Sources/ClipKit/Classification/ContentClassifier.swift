import Foundation

public enum DetectedType: String, Sendable, CaseIterable {
    case link, email, phone, address, date, otp, card
}

public struct Classification: Sendable, Equatable {
    public var types: Set<DetectedType>
    /// True when the whole trimmed text is exactly one http(s) link.
    public var isSingleURL: Bool
    public var isSensitive: Bool { types.contains(.otp) || types.contains(.card) }
}

public enum ContentClassifier {
    public static func classify(_ text: String) -> Classification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var types: Set<DetectedType> = []
        var singleURL = false

        if isCardLike(trimmed) { types.insert(.card) }
        if isOTPLike(trimmed) { types.insert(.otp) }

        // Skip data detection for huge blobs of text; it is slow and not useful there.
        if trimmed.count <= 5_000, let detector = Self.detector {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            for match in detector.matches(in: trimmed, options: [], range: range) {
                switch match.resultType {
                case .link:
                    if match.url?.scheme?.lowercased() == "mailto" {
                        types.insert(.email)
                    } else {
                        types.insert(.link)
                        if match.range == range,
                           let scheme = match.url?.scheme?.lowercased(),
                           scheme == "http" || scheme == "https" {
                            singleURL = true
                        }
                    }
                case .phoneNumber: types.insert(.phone)
                case .address: types.insert(.address)
                case .date: types.insert(.date)
                default: break
                }
            }
        }
        return Classification(types: types, isSingleURL: singleURL)
    }

    /// 4–8 digits, optionally grouped with one space or hyphen, in short text.
    public static func isOTPLike(_ s: String) -> Bool {
        guard s.count <= 12 else { return false }
        let digits = s.filter(\.isASCIIDigit)
        guard (4...8).contains(digits.count) else { return false }
        return s.allSatisfy { $0.isASCIIDigit || $0 == " " || $0 == "-" }
    }

    /// 13–19 digits (spaces/hyphens allowed) that pass the Luhn checksum.
    public static func isCardLike(_ s: String) -> Bool {
        guard s.count <= 32,
              s.allSatisfy({ $0.isASCIIDigit || $0 == " " || $0 == "-" }) else { return false }
        let digits = s.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return false }
        return luhnValid(digits)
    }

    static func luhnValid(_ digits: [Int]) -> Bool {
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    // NSDataDetector is not Sendable; build per call site via a computed property.
    private static var detector: NSDataDetector? {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address, .date]
        return try? NSDataDetector(types: types.rawValue)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
