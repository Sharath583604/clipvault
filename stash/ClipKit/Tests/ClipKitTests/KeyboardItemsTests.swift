import Foundation
import Testing
@testable import ClipKit

@Suite struct KeyboardItemsTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func textOnlyPinnedFirstAndTextStripped() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        try await s.add(NewClip(text: "old", captureMethod: .share), now: t0)
        let pin = try await s.add(NewClip(text: "pinned", captureMethod: .share), now: t0.addingTimeInterval(1))
        try await s.pin(id: pin.id, pinned: true)
        try await s.add(NewClip(text: "new", captureMethod: .share), now: t0.addingTimeInterval(2))
        try await s.ingest(.image(makePNG(width: 16, height: 16)), method: .share, now: t0.addingTimeInterval(3))

        let rows = try await s.keyboardItems(now: t0.addingTimeInterval(10))
        #expect(rows.map(\.preview) == ["pinned", "new", "old"])
        #expect(rows.allSatisfy { $0.text == nil && $0.kind != .image })
        // the full text is still reachable on demand
        #expect(try await s.item(id: rows[0].id)?.text == "pinned")
    }

    @Test func neverMoreThanFiftyRows() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        for i in 0..<80 { try await s.add(NewClip(text: "clip \(i)", captureMethod: .share), now: t0.addingTimeInterval(Double(i))) }
        #expect(try await s.keyboardItems(limit: 500, now: t0.addingTimeInterval(100)).count == 50)
        #expect(try await s.keyboardItems(limit: 5, now: t0.addingTimeInterval(100)).count == 5)
    }

    @Test func expiredItemsAreHidden() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        try await s.add(NewClip(text: "123456", captureMethod: .share), now: t0)
        #expect(try await s.keyboardItems(now: t0.addingTimeInterval(60)).count == 1)
        #expect(try await s.keyboardItems(now: t0.addingTimeInterval(700)).isEmpty)
    }

    @Test func footprintIsReadable() {
        #expect((MemoryFootprint.currentBytes() ?? 0) > 0)
    }
}

@Suite struct WidgetAndChangeTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func widgetItemsAreTheNewestTwoNonSensitive() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        let first = try await s.add(NewClip(text: "first", captureMethod: .share), now: t0)
        try await s.add(NewClip(text: "second", captureMethod: .share), now: t0.addingTimeInterval(1))
        try await s.add(NewClip(text: "123456", captureMethod: .share), now: t0.addingTimeInterval(2))
        try await s.add(NewClip(text: "third", captureMethod: .share), now: t0.addingTimeInterval(3))
        try await s.ingest(.image(makePNG(width: 8, height: 8)), method: .share, now: t0.addingTimeInterval(4))
        // pinning an old item must not push it ahead of newer copies
        try await s.pin(id: first.id, pinned: true)

        let rows = try await s.widgetItems(now: t0.addingTimeInterval(10))
        #expect(rows.map(\.preview) == ["third", "second"])
        #expect(rows.allSatisfy { $0.text == nil && !$0.isSensitive })
        #expect(try await s.keyboardItems(now: t0.addingTimeInterval(10)).count == 4)
    }

    @Test func copyStateExpiresAfterWindow() {
        let state = WidgetCopyState(suiteName: "WidgetCopyStateTests-\(UUID().uuidString)")
        let id = UUID()
        #expect(state.recentlyCopiedID(now: t0) == nil)
        state.record(id: id, now: t0)
        #expect(state.recentlyCopiedID(now: t0.addingTimeInterval(30)) == id)
        #expect(state.recentlyCopiedID(now: t0.addingTimeInterval(61)) == nil)
    }

    @Test func keyboardCaptureSettingsAndSharedCounter() {
        let s = ClipSettings(suiteName: "KbCaptureTests-\(UUID().uuidString)")
        #expect(s.keyboardAutoSave == true)
        s.keyboardAutoSave = false
        #expect(s.keyboardAutoSave == false)
        #expect(s.lastHandledPasteboardChangeCount == 0)
        s.lastHandledPasteboardChangeCount = 42
        #expect(s.lastHandledPasteboardChangeCount == 42)
    }

    @Test func copyAfterShareDefaultsOnAndPersists() {
        let s = ClipSettings(suiteName: "CopyAfterShareTests-\(UUID().uuidString)")
        #expect(s.copyAfterShare == true)
        s.copyAfterShare = false
        #expect(s.copyAfterShare == false)
    }

    @Test func autoSaveSettingDefaultsOff() {
        let s = ClipSettings(suiteName: "AutoSaveTests-\(UUID().uuidString)")
        #expect(s.autoSaveOnOpen == false)
        s.autoSaveOnOpen = true
        #expect(s.autoSaveOnOpen)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    @Test func changeHookFiresOnWritesOnly() async throws {
        let counter = Counter()
        let s = try ClipStore.open(location: makeTempLocation(), onChange: { counter.bump() })
        let v = try await s.add(NewClip(text: "a", captureMethod: .share), now: t0)
        try await s.pin(id: v.id, pinned: true)
        try await s.delete(id: v.id)
        #expect(counter.value == 3)
        _ = try await s.recent(limit: 5)
        _ = try await s.widgetItems()
        #expect(counter.value == 3)
    }
}

@Suite struct ExpiryHardeningTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func expiredItemIsNotFetchableById() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        let otp = try await s.add(NewClip(text: "123456", captureMethod: .share), now: t0)
        #expect(try await s.item(id: otp.id, now: t0.addingTimeInterval(60))?.text == "123456")
        #expect(try await s.item(id: otp.id, now: t0.addingTimeInterval(601)) == nil)
    }

    @Test func savingPurgesExpiredRows() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        let otp = try await s.add(NewClip(text: "123456", captureMethod: .share), now: t0)
        // Any later save, from any process, cleans up the expired row.
        try await s.add(NewClip(text: "hello", captureMethod: .share), now: t0.addingTimeInterval(700))
        #expect(try await s.purgeExpired(now: t0.addingTimeInterval(700)) == 0)
        #expect(try await s.item(id: otp.id, now: t0) == nil)
    }
}
