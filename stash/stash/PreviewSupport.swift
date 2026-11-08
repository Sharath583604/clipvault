import Foundation
import ClipKit

extension ClipItemValue {
    static var samples: [ClipItemValue] {
        let now = Date()
        func make(_ text: String, preview: String? = nil, kind: ClipKind = .text, pinned: Bool = false,
                  sensitive: Bool = false, age: TimeInterval) -> ClipItemValue {
            ClipItemValue(id: UUID(), createdAt: now.addingTimeInterval(-age), kind: kind, text: text,
                          preview: preview ?? text, blobPath: nil, contentHash: text, isPinned: pinned,
                          expiresAt: sensitive ? now.addingTimeInterval(500) : nil, isSensitive: sensitive,
                          captureMethod: .pasteButton)
        }
        return [
            make("https://developer.apple.com/documentation/swiftui", kind: .url, pinned: true, age: 3600),
            make("Meeting notes: ship M2 on Friday, then start on the keyboard extension.", age: 60),
            make("482913", preview: "••••••", sensitive: true, age: 30),
        ]
    }
}

extension AppModel {
    /// Preview model backed by a throwaway store in the temp directory.
    static func preview(seed: Bool = true) -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVaultPreview-\(UUID().uuidString)", isDirectory: true)
        guard let store = try? ClipStore.open(location: StorageLocation(directory: dir)) else {
            return AppModel(store: nil)
        }
        if seed {
            Task {
                for sample in ClipItemValue.samples.reversed() {
                    if let text = sample.text {
                        let item = try? await store.add(NewClip(text: text, captureMethod: .pasteButton))
                        if let item, sample.isPinned { try? await store.pin(id: item.id, pinned: true) }
                    }
                }
            }
        }
        return AppModel(store: store)
    }
}

struct PreviewAuthenticator: Authenticating {
    func canAuthenticate() -> Bool { true }
    func authenticate(reason: String) async -> Bool { true }
}

extension AppLock {
    static func preview() -> AppLock {
        AppLock(authenticator: PreviewAuthenticator(), settings: ClipSettings(suiteName: "ClipVaultPreview"))
    }
}
