import Foundation
import Testing
@testable import ClipKit

@Suite struct SensitivePolicyTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func masking() {
        let p = SensitivePolicy()
        #expect(p.preview(for: "4242 4242 4242 4242",
                          classification: ContentClassifier.classify("4242 4242 4242 4242")) == "•••• •••• •••• 4242")
        #expect(p.preview(for: "1234", classification: ContentClassifier.classify("1234")) == "••••")
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        let p = SensitivePolicy(maxPreviewLength: 10)
        let text = "a   b\n\nc dddddddddddd"
        #expect(p.preview(for: text, classification: ContentClassifier.classify(text)) == "a b c dddd")
    }

    @Test func expiry() {
        let p = SensitivePolicy(retentionDays: 7)
        #expect(p.expiry(isSensitive: true, from: now) == now.addingTimeInterval(600))
        #expect(p.expiry(isSensitive: false, from: now) == now.addingTimeInterval(7 * 86_400))
        #expect(SensitivePolicy(retentionDays: 0).expiry(isSensitive: false, from: now) == nil)
    }
}
