import Foundation
import Testing
@testable import ClipKit

/// Two independent ModelContainers/ModelContexts over one SQLite file stand in for two
/// processes (app + keyboard). This does not prove behavior across real processes on
/// device; see the README manual checklist.
@Suite struct CrossProcessTests {
    @Test func secondStoreSeesWritesFromFirst() async throws {
        let loc = try makeTempLocation()
        let app = try ClipStore.open(location: loc)
        let keyboard = try ClipStore.open(location: loc)
        let v = try await app.add(NewClip(text: "from app", captureMethod: .share))
        let seen = try await keyboard.recent(limit: 5)
        #expect(seen.map(\.id) == [v.id])
        #expect(seen.first?.text == "from app")
    }

    @Test func writesInBothDirectionsConverge() async throws {
        let loc = try makeTempLocation()
        let a = try ClipStore.open(location: loc)
        let b = try ClipStore.open(location: loc)
        try await a.add(NewClip(text: "one", captureMethod: .share))
        try await b.add(NewClip(text: "two", captureMethod: .keyboard))
        #expect(try await a.recent(limit: 10).count == 2)
        #expect(try await b.recent(limit: 10).count == 2)
        // Dedupe works across stores too.
        try await b.add(NewClip(text: "one", captureMethod: .keyboard))
        #expect(try await a.recent(limit: 10).count == 2)
    }

    @Test func concurrentWritersDoNotLoseData() async throws {
        let loc = try makeTempLocation()
        let a = try ClipStore.open(location: loc)
        let b = try ClipStore.open(location: loc)
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { try await a.add(NewClip(text: "a\(i)", captureMethod: .share)) }
                group.addTask { try await b.add(NewClip(text: "b\(i)", captureMethod: .keyboard)) }
            }
            try? await group.waitForAll()
        }
        #expect(try await a.recent(limit: 100).count == 40)
    }
}
