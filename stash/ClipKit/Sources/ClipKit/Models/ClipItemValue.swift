import Foundation

/// Sendable snapshot of a stored clip, safe to hand to UI, widgets and the keyboard.
public struct ClipItemValue: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let kind: ClipKind
    public let text: String?
    public let preview: String
    public let blobPath: String?
    public let contentHash: String
    public let isPinned: Bool
    public let expiresAt: Date?
    public let isSensitive: Bool
    public let captureMethod: CaptureMethod

    public init(id: UUID, createdAt: Date, kind: ClipKind, text: String?, preview: String,
                blobPath: String?, contentHash: String, isPinned: Bool, expiresAt: Date?,
                isSensitive: Bool, captureMethod: CaptureMethod) {
        self.id = id; self.createdAt = createdAt; self.kind = kind; self.text = text
        self.preview = preview; self.blobPath = blobPath; self.contentHash = contentHash
        self.isPinned = isPinned; self.expiresAt = expiresAt; self.isSensitive = isSensitive
        self.captureMethod = captureMethod
    }
}

public extension ClipItemValue {
    /// Same item without its full text, so list UIs (the keyboard) hold only the preview.
    func strippingText() -> ClipItemValue {
        ClipItemValue(id: id, createdAt: createdAt, kind: kind, text: nil, preview: preview,
                      blobPath: blobPath, contentHash: contentHash, isPinned: isPinned,
                      expiresAt: expiresAt, isSensitive: isSensitive, captureMethod: captureMethod)
    }
}

/// Input for `ClipStore.add`.
public struct NewClip: Sendable {
    public let kind: ClipKind
    public let text: String?
    public let preview: String?
    public let blobPath: String?
    public let contentHash: String
    public let captureMethod: CaptureMethod

    /// Text or URL clip. The kind is refined by the classifier if `.text` is passed and the
    /// whole string is a single link.
    public init(text: String, captureMethod: CaptureMethod) {
        self.kind = .text
        self.text = text
        self.preview = nil
        self.blobPath = nil
        self.contentHash = ContentHash.hash(text: text)
        self.captureMethod = captureMethod
    }

    /// Image or file clip stored as a blob. `dataHash` should be a hash of the bytes.
    public init(blobKind: ClipKind, blobPath: String, dataHash: String, preview: String,
                captureMethod: CaptureMethod) {
        self.kind = blobKind
        self.text = nil
        self.preview = preview
        self.blobPath = blobPath
        self.contentHash = dataHash
        self.captureMethod = captureMethod
    }
}
