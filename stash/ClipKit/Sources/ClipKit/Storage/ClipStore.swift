import Foundation
import SwiftData
import os

/// Single entry point for reading and writing clips. Every process (app, share extension,
/// keyboard, widget, intents) opens its own `ClipStore` on the same SQLite file in the
/// App Group; SQLite WAL handles cross-process locking.
public actor ClipStore: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private let location: StorageLocation
    private let search: any SearchProvider
    private let onChange: (@Sendable () -> Void)?
    private let log = Logger(subsystem: "ClipKit", category: "ClipStore")

    /// Hard cap on stored text so a huge paste cannot bloat the keyboard's memory.
    public static let maxTextLength = 100_000

    init(container: ModelContainer, location: StorageLocation, search: any SearchProvider,
         onChange: (@Sendable () -> Void)?) {
        self.onChange = onChange
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        self.location = location
        self.search = search
    }

    /// - Parameter onChange: called after every successful write (pass `WidgetRefresh.reload`
    ///   from processes that should refresh widgets).
    public static func open(location: StorageLocation,
                            search: any SearchProvider = SubstringSearchProvider(),
                            onChange: (@Sendable () -> Void)? = nil) throws -> ClipStore {
        try location.prepare()
        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration(schema: schema, url: location.storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ClipStore(container: container, location: location, search: search, onChange: onChange)
    }

    // MARK: - Writes

    /// Adds a clip. If an item with the same content hash exists it is not duplicated:
    /// its `createdAt` is bumped to `now` and its expiry refreshed.
    @discardableResult
    public func add(_ clip: NewClip, policy: SensitivePolicy = SensitivePolicy(),
                    now: Date = Date()) throws -> ClipItemValue {
        if let existing = try fetchOne(hash: clip.contentHash) {
            existing.createdAt = now
            if !existing.isPinned || existing.isSensitive {
                existing.expiresAt = policy.expiry(isSensitive: existing.isSensitive, from: now)
            }
            try modelContext.save()
            onChange?()
            return existing.value
        }

        // Expired rows are removed opportunistically by whichever process saves next.
        _ = try? purgeExpired(now: now)

        var kind = clip.kind
        let text = clip.text.map { String($0.prefix(Self.maxTextLength)) }
        var sensitive = false
        var preview = clip.preview ?? ""

        if let t = text, clip.kind == .text {
            let classification = ContentClassifier.classify(t)
            sensitive = classification.isSensitive
            if classification.isSingleURL { kind = .url }
            preview = policy.preview(for: t, classification: classification)
        }

        let item = ClipItem(createdAt: now, kind: kind, text: text, preview: preview,
                            blobPath: clip.blobPath, contentHash: clip.contentHash,
                            expiresAt: policy.expiry(isSensitive: sensitive, from: now),
                            isSensitive: sensitive, captureMethod: clip.captureMethod)
        modelContext.insert(item)
        try modelContext.save()
        onChange?()
        return item.value
    }

    /// Saves a payload from PasteButton, the share sheet or an intent. Returns nil when the
    /// payload cannot be stored (for example an undecodable image).
    @discardableResult
    public func ingest(_ payload: IngestPayload, method: CaptureMethod,
                       policy: SensitivePolicy = SensitivePolicy(),
                       now: Date = Date()) throws -> ClipItemValue? {
        switch payload {
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try add(NewClip(text: text, captureMethod: method), policy: policy, now: now)
        case .url(let url):
            return try add(NewClip(text: url.absoluteString, captureMethod: method), policy: policy, now: now)
        case .image(let data):
            guard let image = ImageIngest.normalize(data) else { return nil }
            let hash = ContentHash.hash(data: image.jpegData)
            let name = "\(hash).jpg"
            let target = location.blobsDirectory.appendingPathComponent(name)
            let wroteFile = !FileManager.default.fileExists(atPath: target.path)
            if wroteFile { try image.jpegData.write(to: target, options: .atomic) }
            do {
                return try add(NewClip(blobKind: .image, blobPath: name, dataHash: hash,
                                       preview: String(localized: "Image \(String(image.width))×\(String(image.height))", bundle: .module),
                                       captureMethod: method), policy: policy, now: now)
            } catch {
                if wroteFile { try? FileManager.default.removeItem(at: target) }
                throw error
            }
        }
    }

    /// Pinning keeps ordinary items past their retention expiry. Sensitive items always expire.
    public func pin(id: UUID, pinned: Bool, policy: SensitivePolicy = SensitivePolicy(),
                    now: Date = Date()) throws {
        guard let item = try fetchOne(id: id) else { return }
        item.isPinned = pinned
        if !item.isSensitive {
            item.expiresAt = pinned ? nil : policy.expiry(isSensitive: false, from: item.createdAt)
        }
        try modelContext.save()
        onChange?()
    }

    public func delete(id: UUID) throws {
        guard let item = try fetchOne(id: id) else { return }
        removeBlob(item.blobPath)
        modelContext.delete(item)
        try modelContext.save()
        onChange?()
    }

    /// Removes every clip, including pinned ones, and their blobs.
    public func deleteAll() throws {
        for item in try modelContext.fetch(FetchDescriptor<ClipItem>()) {
            removeBlob(item.blobPath)
            modelContext.delete(item)
        }
        try modelContext.save()
        onChange?()
    }

    /// Removes everything whose expiry has passed. Returns the number removed.
    @discardableResult
    public func purgeExpired(now: Date = Date()) throws -> Int {
        let expired = try modelContext.fetch(FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.expiresAt != nil && ($0.expiresAt ?? now) <= now }))
        for item in expired {
            removeBlob(item.blobPath)
            modelContext.delete(item)
        }
        if !expired.isEmpty { try modelContext.save(); onChange?() }
        return expired.count
    }

    // MARK: - Reads

    public func recent(limit: Int, now: Date = Date()) throws -> [ClipItemValue] {
        var d = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.expiresAt == nil || ($0.expiresAt ?? now) > now },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = max(0, limit)
        return try modelContext.fetch(d).map(\.value)
    }

    public func pinned(limit: Int = 50, now: Date = Date()) throws -> [ClipItemValue] {
        var d = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.isPinned && ($0.expiresAt == nil || ($0.expiresAt ?? now) > now) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = max(0, limit)
        return try modelContext.fetch(d).map(\.value)
    }

    public func search(_ query: String, limit: Int = 200, now: Date = Date()) throws -> [ClipItemValue] {
        let all = try modelContext.fetch(FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.expiresAt == nil || ($0.expiresAt ?? now) > now },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).map(\.value)
        return Array(search.rank(query: query, in: all).prefix(max(0, limit)))
    }

    /// Rows for the keyboard: text and link items only (never images or files), pinned first,
    /// at most `limit` rows in total. Values carry the preview but not the full text; fetch the
    /// text with `item(id:)` when the user taps a row. This keeps the keyboard's memory small.
    public func keyboardItems(limit: Int = 50, now: Date = Date()) throws -> [ClipItemValue] {
        try textRows(limit: limit, includeSensitive: true, now: now)
    }

    /// The most recent text/link clips for widgets, newest first (pinning does not reorder them).
    /// Never includes sensitive items, since widgets can be seen on the Lock Screen and Home Screen.
    /// Values carry the preview only; fetch the text with `item(id:)` when copying.
    public func widgetItems(limit: Int = 2, now: Date = Date()) throws -> [ClipItemValue] {
        var fetch = FetchDescriptor<ClipItem>(
            predicate: #Predicate {
                ($0.kindRaw == "text" || $0.kindRaw == "url") && !$0.isSensitive
                    && ($0.expiresAt == nil || ($0.expiresAt ?? now) > now)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        fetch.fetchLimit = max(0, min(limit, 50))
        return try modelContext.fetch(fetch).map { $0.value.strippingText() }
    }

    private func textRows(limit: Int, includeSensitive: Bool, now: Date) throws -> [ClipItemValue] {
        let cap = max(0, min(limit, 50))
        var pinnedFetch = FetchDescriptor<ClipItem>(
            predicate: #Predicate {
                $0.isPinned && ($0.kindRaw == "text" || $0.kindRaw == "url")
                    && (includeSensitive || !$0.isSensitive)
                    && ($0.expiresAt == nil || ($0.expiresAt ?? now) > now)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        pinnedFetch.fetchLimit = cap
        let pinned = try modelContext.fetch(pinnedFetch).map { $0.value.strippingText() }
        guard pinned.count < cap else { return pinned }

        var recentFetch = FetchDescriptor<ClipItem>(
            predicate: #Predicate {
                !$0.isPinned && ($0.kindRaw == "text" || $0.kindRaw == "url")
                    && (includeSensitive || !$0.isSensitive)
                    && ($0.expiresAt == nil || ($0.expiresAt ?? now) > now)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recentFetch.fetchLimit = cap - pinned.count
        return pinned + (try modelContext.fetch(recentFetch).map { $0.value.strippingText() })
    }

    /// Returns nil for unknown ids and for items past their expiry, so a stale keyboard row or
    /// shortcut cannot resurrect an expired one-time code.
    public func item(id: UUID, now: Date = Date()) throws -> ClipItemValue? {
        guard let item = try fetchOne(id: id) else { return nil }
        if let expiry = item.expiresAt, expiry <= now { return nil }
        return item.value
    }

    public nonisolated func blobURL(for item: ClipItemValue) -> URL? {
        item.blobPath.map { location.blobsDirectory.appendingPathComponent($0) }
    }

    // MARK: - Helpers

    private func fetchOne(hash: String) throws -> ClipItem? {
        var d = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func fetchOne(id: UUID) throws -> ClipItem? {
        var d = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func removeBlob(_ relativePath: String?) {
        guard let relativePath else { return }
        let url = location.blobsDirectory.appendingPathComponent(relativePath)
        do { try FileManager.default.removeItem(at: url) }
        catch { log.error("Blob removal failed: \(error.localizedDescription, privacy: .public)") }
    }
}
