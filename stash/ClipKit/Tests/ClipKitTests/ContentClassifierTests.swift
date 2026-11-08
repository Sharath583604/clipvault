import Testing
@testable import ClipKit

@Suite struct ContentClassifierTests {
    @Test func detectsLink() {
        let c = ContentClassifier.classify("https://apple.com/swift")
        #expect(c.types.contains(.link))
        #expect(c.isSingleURL)
        #expect(!ContentClassifier.classify("see https://apple.com now").isSingleURL)
    }

    @Test func detectsEmailPhoneDate() {
        #expect(ContentClassifier.classify("me@example.com").types.contains(.email))
        #expect(ContentClassifier.classify("call +1 415 555 0132 today").types.contains(.phone))
        #expect(ContentClassifier.classify("meet on December 25, 2030").types.contains(.date))
    }

    @Test func detectsAddress() {
        let c = ContentClassifier.classify("1 Infinite Loop, Cupertino, CA 95014")
        #expect(c.types.contains(.address))
    }

    @Test func otpRules() {
        #expect(ContentClassifier.isOTPLike("1234"))
        #expect(ContentClassifier.isOTPLike("12345678"))
        #expect(ContentClassifier.isOTPLike("123 456"))
        #expect(!ContentClassifier.isOTPLike("123"))
        #expect(!ContentClassifier.isOTPLike("123456789"))
        #expect(!ContentClassifier.isOTPLike("code 123456"))
    }

    @Test func cardRulesUseLuhn() {
        #expect(ContentClassifier.isCardLike("4242 4242 4242 4242"))
        #expect(ContentClassifier.isCardLike("4111111111111111"))
        #expect(!ContentClassifier.isCardLike("4242 4242 4242 4241"))
        #expect(!ContentClassifier.isCardLike("1234"))
        let c = ContentClassifier.classify("4242424242424242")
        #expect(c.isSensitive && c.types.contains(.card))
    }

    @Test func plainTextIsNotSensitive() {
        #expect(!ContentClassifier.classify("hello world").isSensitive)
    }
}
