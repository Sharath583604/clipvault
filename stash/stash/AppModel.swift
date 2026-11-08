import SwiftUI
import UIKit
import ClipKit
import os

/// Drives the main screen. Owns the store handle and the only code that touches
/// `UIPasteboard.general`.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case ready
        case storageUnavailable
    }

    private(set) var items: [ClipItemValue] = []
    private(set) var status: Status
    private(set) var showClipboardHint = false
    /// Set briefly after a copy-back or save so the UI can confirm it.
    private(set) var toast: String?
    /// Last query the list was loaded for, so saves can refresh the visible list.
    private(set) var currentQuery = ""
    private var isAutoSaving = false

    let store: ClipStore?
    private let settings: ClipSettings
    private let log = Logger(subsystem: "com.sclera.clipvault", category: "AppModel")

    init(store: ClipStore?, settings: ClipSettings = ClipSettings()) {
        self.store = store
        self.settings = settings
        self.status = store == nil ? .storageUnavailable : .ready
    }

    static func live() -> AppModel {
        do {
            let store = try ClipStore.open(location: StorageLocation.appGroup(),
                                           onChange: WidgetRefresh.reload)
            return AppModel(store: store)
        } catch {
            Logger(subsystem: "com.sclera.clipvault", category: "AppModel")
                .error("Storage unavailable: \(error.localizedDescription, privacy: .public)")
            return AppModel(store: nil)
        }
    }

    // MARK: - Loading

    func reload(query: String, purge: Bool = true) async {
        guard let store else { return }
        currentQuery = query
        do {
            if purge { try await store.purgeExpired() }
            items = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? try await store.recent(limit: 500)
                : try await store.search(query)
        } catch {
            log.error("Reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts a just-saved item at the top immediately (when no search is active) so the list does
    /// not wait for a database round trip. A normal reload follows and corrects any difference.
    private func show(_ saved: ClipItemValue) {
        guard currentQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        items.removeAll { $0.id == saved.id }
        items.insert(saved, at: 0)
    }

    // MARK: - Capture

    /// Called from `PasteButton`. The system grants read access for this one paste.
    func save(providers: [NSItemProvider]) async {
        guard store != nil else { return }
        let payloads = await ProviderIngest.payloads(from: providers)
        markClipboardHandled()
        let saved = await ingest(payloads, method: .pasteButton)
        showToast(saved > 0 ? String(localized: "Saved to ClipVault") : String(localized: "Nothing to save"))
    }

    /// Saves payloads, showing each item in the list as soon as it is stored, then refreshes.
    @discardableResult
    private func ingest(_ payloads: [IngestPayload], method: CaptureMethod) async -> Int {
        guard let store else { return 0 }
        var saved = 0
        for payload in payloads {
            do {
                if let item = try await store.ingest(payload, method: method, policy: settings.policy) {
                    saved += 1
                    show(item)
                }
            } catch {
                log.error("Save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if saved > 0 { await reload(query: currentQuery, purge: false) }
        return saved
    }

    // MARK: - Foreground handling

    /// Runs whenever the app becomes active. If the user opted in, reads the clipboard once per
    /// copy; otherwise only updates the "new item on clipboard" hint.
    func handleForeground() async {
        if settings.autoSaveOnOpen { await autoSaveClipboard() }
        refreshClipboardHint()
        await reload(query: currentQuery)
    }

    /// Opt-in. iOS shows its paste prompt for this read unless the user set
    /// Settings > ClipVault > Paste from Other Apps to Allow. It can only run while the app is
    /// open: iOS never reports copies made while ClipVault is in the background.
    private func autoSaveClipboard() async {
        let pasteboard = UIPasteboard.general
        guard !isAutoSaving, pasteboard.changeCount != lastHandledChangeCount,
              pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages else { return }
        isAutoSaving = true
        defer { isAutoSaving = false }

        let payload: IngestPayload?
        if pasteboard.hasURLs, let url = pasteboard.url, !url.isFileURL { payload = .url(url) }
        else if pasteboard.hasStrings, let text = pasteboard.string { payload = .text(text) }
        else if pasteboard.hasImages, let data = pasteboard.image?.pngData() { payload = .image(data) }
        else { payload = nil }

        // Mark handled even when nothing was readable (prompt declined), so we do not re-ask
        // until the clipboard changes again.
        markClipboardHandled()
        guard let payload else { return }
        if await ingest([payload], method: .foregroundRead) > 0 {
            showToast(String(localized: "Saved clipboard to ClipVault"))
        }
    }

    // MARK: - Foreground clipboard hint

    /// Uses only non-notifying pasteboard properties: `changeCount`, `hasStrings`, `hasURLs`
    /// and `hasImages`. Never reads the contents. (Whether `hasImages` is also silent is on
    /// the README's device checklist.)
    func refreshClipboardHint() {
        let pasteboard = UIPasteboard.general
        let changed = pasteboard.changeCount != lastHandledChangeCount
        let hasContent = pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages
        showClipboardHint = changed && hasContent
    }

    func dismissClipboardHint() {
        markClipboardHandled()
    }

    private var lastHandledChangeCount: Int {
        get { settings.lastHandledPasteboardChangeCount }
        set { settings.lastHandledPasteboardChangeCount = newValue }
    }

    private func markClipboardHandled() {
        lastHandledChangeCount = UIPasteboard.general.changeCount
        showClipboardHint = false
    }

    // MARK: - Item actions

    /// Writes the item back to the system pasteboard. Writing does not trigger the paste alert.
    func copy(_ item: ClipItemValue) {
        let outcome = PasteboardWriter.write(item, blobURL: store?.blobURL(for: item))
        guard outcome == .copied else {
            showToast(String(localized: "This item is no longer available"))
            return
        }
        lastHandledChangeCount = UIPasteboard.general.changeCount
        showClipboardHint = false
        showToast(String(localized: "Copied"))
    }

    func togglePin(_ item: ClipItemValue, query: String) async {
        guard let store else { return }
        do {
            try await store.pin(id: item.id, pinned: !item.isPinned, policy: settings.policy)
            await reload(query: query)
        } catch {
            log.error("Pin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ item: ClipItemValue, query: String) async {
        guard let store else { return }
        do {
            try await store.delete(id: item.id)
            await reload(query: query)
        } catch {
            log.error("Delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearAll() async {
        guard let store else { return }
        do {
            try await store.deleteAll()
            items = []
        } catch {
            log.error("Clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func thumbnailURL(for item: ClipItemValue) -> URL? { store?.blobURL(for: item) }

    private func showToast(_ message: String) {
        toast = message
        UIAccessibility.post(notification: .announcement, argument: message)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if self?.toast == message { self?.toast = nil }
        }
    }
}
