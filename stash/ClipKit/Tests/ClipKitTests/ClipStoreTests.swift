import Foundation
import Testing
@testable import ClipKit

@Suite struct ClipStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func store() throws -> ClipStore {
        try ClipStore.open(location: makeTempLocation())
    }

    @Test func addAndRecentOrdering() async throws {
        let s = try store()
        try await s.add(NewClip(text: "first", captureMethod: .pasteButton), now: t0)
        try await s.add(NewClip(text: "second", captureMethod: .share), now: t0.addingTimeInterval(10))
        let recent = try await s.recent(limit: 10, now: t0.addingTimeInterval(20))
        #expect(recent.map(\.text) == ["second", "first"])
        #expect(recent.first?.captureMethod == .share)
        let limited = try await s.recent(limit: 1, now: t0.addingTimeInterval(20))
        #expect(limited.count == 1)
    }

    @Test func dedupeBumpsCreatedAt() async throws {
        let s = try store()
        let a = try await s.add(NewClip(text: "same", captureMethod: .pasteButton), now: t0)
        try await s.add(NewClip(text: "other", captureMethod: .pasteButton), now: t0.addingTimeInterval(5))
        let b = try await s.add(NewClip(text: "same", captureMethod: .pasteButton), now: t0.addingTimeInterval(10))
        #expect(a.id == b.id)
        let recent = try await s.recent(limit: 10, now: t0.addingTimeInterval(11))
        #expect(recent.count == 2)
        #expect(recent.first?.id == a.id)
        #expect(recent.first?.createdAt == t0.addingTimeInterval(10))
    }

    @Test func searchIsCaseInsensitiveSubstring() async throws {
        let s = try store()
        try await s.add(NewClip(text: "Hello World", captureMethod: .pasteButton), now: t0)
        try await s.add(NewClip(text: "goodbye", captureMethod: .pasteButton), now: t0)
        #expect(try await s.search("WORLD", now: t0).count == 1)
        #expect(try await s.search("o", now: t0).count == 2)
        #expect(try await s.search("zzz", now: t0).isEmpty)
        #expect(try await s.search("  ", now: t0).count == 2)
    }

    @Test func sensitiveItemsAreMaskedAndNotSearchableByValue() async throws {
        let s = try store()
        let otp = try await s.add(NewClip(text: "482913", captureMethod: .pasteButton), now: t0)
        #expect(otp.isSensitive)
        #expect(otp.preview == "••••••")
        #expect(otp.expiresAt == t0.addingTimeInterval(600))
        #expect(otp.text == "482913") // retained so it can be pasted back
        #expect(try await s.search("4829", now: t0).isEmpty)
    }

    @Test func urlKindIsRefined() async throws {
        let s = try store()
        let v = try await s.add(NewClip(text: "https://example.com/a", captureMethod: .share), now: t0)
        #expect(v.kind == .url)
    }

    @Test func expiryAndPurge() async throws {
        let s = try store()
        let policy = SensitivePolicy(retentionDays: 1)
        try await s.add(NewClip(text: "ordinary", captureMethod: .pasteButton), policy: policy, now: t0)
        try await s.add(NewClip(text: "123456", captureMethod: .pasteButton), policy: policy, now: t0)
        // after 11 minutes the OTP is hidden from reads and purgeable
        let later = t0.addingTimeInterval(11 * 60)
        #expect(try await s.recent(limit: 10, now: later).map(\.text) == ["ordinary"])
        #expect(try await s.purgeExpired(now: later) == 1)
        // after 2 days the ordinary item goes too
        let muchLater = t0.addingTimeInterval(2 * 86_400)
        #expect(try await s.purgeExpired(now: muchLater) == 1)
        #expect(try await s.recent(limit: 10, now: muchLater).isEmpty)
    }

    @Test func pinnedItemsSurviveRetention() async throws {
        let s = try store()
        let policy = SensitivePolicy(retentionDays: 1)
        let v = try await s.add(NewClip(text: "keep me", captureMethod: .pasteButton), policy: policy, now: t0)
        try await s.pin(id: v.id, pinned: true, policy: policy, now: t0)
        let muchLater = t0.addingTimeInterval(10 * 86_400)
        #expect(try await s.purgeExpired(now: muchLater) == 0)
        #expect(try await s.pinned(now: muchLater).count == 1)
        try await s.pin(id: v.id, pinned: false, policy: policy, now: muchLater)
        #expect(try await s.purgeExpired(now: muchLater) == 1)
    }

    @Test func retentionZeroKeepsForever() async throws {
        let s = try store()
        let v = try await s.add(NewClip(text: "x", captureMethod: .pasteButton),
                                policy: SensitivePolicy(retentionDays: 0), now: t0)
        #expect(v.expiresAt == nil)
    }

    @Test func deleteRemovesItemAndBlob() async throws {
        let loc = try makeTempLocation()
        let s = try ClipStore.open(location: loc)
        let blob = loc.blobsDirectory.appendingPathComponent("a.png")
        try Data([1, 2, 3]).write(to: blob)
        let v = try await s.add(NewClip(blobKind: .image, blobPath: "a.png",
                                        dataHash: ContentHash.hash(data: Data([1, 2, 3])),
                                        preview: "Image", captureMethod: .share), now: t0)
        try await s.delete(id: v.id)
        #expect(try await s.item(id: v.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: blob.path))
    }
}
