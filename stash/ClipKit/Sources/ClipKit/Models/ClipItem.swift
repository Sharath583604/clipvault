import Foundation
import SwiftData

public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text, url, image, file
}

public enum CaptureMethod: String, Codable, Sendable, CaseIterable {
    case pasteButton, share, intent, keyboard
    /// Read automatically when the app opened (opt-in setting).
    case foregroundRead
}

/// Persistent row. Internal to ClipKit: callers exchange `ClipItemValue` so nothing
/// non-Sendable crosses an isolation boundary.
@Model
final class ClipItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var kindRaw: String
    var text: String?
    var preview: String
    var blobPath: String?
    @Attribute(.unique) var contentHash: String
    var isPinned: Bool
    var expiresAt: Date?
    var isSensitive: Bool
    var captureMethodRaw: String

    init(id: UUID = UUID(), createdAt: Date, kind: ClipKind, text: String?, preview: String,
         blobPath: String?, contentHash: String, isPinned: Bool = false, expiresAt: Date?,
         isSensitive: Bool, captureMethod: CaptureMethod) {
        self.id = id
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.text = text
        self.preview = preview
        self.blobPath = blobPath
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.expiresAt = expiresAt
        self.isSensitive = isSensitive
        self.captureMethodRaw = captureMethod.rawValue
    }

    var value: ClipItemValue {
        ClipItemValue(id: id, createdAt: createdAt, kind: ClipKind(rawValue: kindRaw) ?? .text,
                      text: text, preview: preview, blobPath: blobPath, contentHash: contentHash,
                      isPinned: isPinned, expiresAt: expiresAt, isSensitive: isSensitive,
                      captureMethod: CaptureMethod(rawValue: captureMethodRaw) ?? .pasteButton)
    }
}
