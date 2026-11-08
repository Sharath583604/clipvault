import SwiftUI
import UIKit
import ClipKit
import os

/// State for the keyboard UI. The store is only opened when Full Access is on, because
/// without it iOS denies the shared App Group container.
@MainActor
@Observable
final class KeyboardModel {
    enum State: Equatable {
        case noFullAccess
        case secureField
        case storageUnavailable
        case empty
        case ready
    }

    /// Closures set by the view controller so the model never touches UIKit directly.
    struct Actions {
        var insert: (String) -> Void = { _ in }
        var deleteBackward: () -> Void = {}
        var returnKey: () -> Void = {}
    }

    private(set) var state: State = .empty
    private(set) var items: [ClipItemValue] = []
    private(set) var lastDebugMessage = ""
    /// Whether copies are saved automatically (shared setting, on by default).
    private(set) var autoSave: Bool
    private var settings = ClipSettings()
    private var watchTask: Task<Void, Never>?
    private var isCapturing = false
    var actions = Actions()

    private(set) var hasFullAccess: Bool
    private(set) var isSecure = false
    private var store: ClipStore?
    private let log = Logger(subsystem: "com.sclera.clipvault.KeyboardExtension", category: "Keyboard")

    init(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        self.autoSave = ClipSettings().keyboardAutoSave
    }

    /// Preview/testing initializer with a fixed state.
    init(previewState: State, items: [ClipItemValue] = []) {
        self.hasFullAccess = previewState != .noFullAccess
        self.autoSave = true
        self.state = previewState
        self.items = items
    }

    func update(hasFullAccess: Bool, isSecure: Bool) {
        self.hasFullAccess = hasFullAccess
        self.isSecure = isSecure
        if hasFullAccess, store == nil {
            do { store = try ClipStore.open(location: StorageLocation.appGroup()) }
            catch { log.error("Store open failed: \(error.localizedDescription, privacy: .public)") }
        }
        refreshState()
    }

    func reload() async {
        guard hasFullAccess, !isSecure, let store else { refreshState(); return }
        do {
            items = try await store.keyboardItems(limit: 50)
        } catch {
            log.error("Load failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
        refreshState()
    }

    // MARK: - Clipboard capture

    func setAutoSave(_ on: Bool) {
        autoSave = on
        settings.keyboardAutoSave = on
    }

    /// Starts reacting to pasteboard changes while the keyboard is on screen. This is the system's
    /// change notification, not polling. Copies made while no ClipVault process is running
    /// cannot be seen; only the latest one survives on the pasteboard.
    func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIPasteboard.changedNotification) {
                await self?.captureClipboardIfNeeded()
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Saves the clipboard if it changed since any ClipVault process last handled it. Text and links
    /// only: the keyboard never decodes images (memory ceiling). Needs Full Access.
    ///
    /// `changeCount`, `hasStrings` and `hasURLs` do not read the contents. The actual read below
    /// may raise iOS's paste prompt; whether it does inside a keyboard is on the device checklist.
    func captureClipboardIfNeeded() async {
        guard autoSave, hasFullAccess, !isSecure, let store, !isCapturing else { return }
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard count != settings.lastHandledPasteboardChangeCount,
              pasteboard.hasStrings || pasteboard.hasURLs else { return }
        isCapturing = true
        defer { isCapturing = false }
        // Mark first so the change notification and viewWillAppear cannot both save the same copy,
        // and so a declined prompt is not re-asked until the clipboard changes again.
        settings.lastHandledPasteboardChangeCount = count

        let payload: IngestPayload?
        if pasteboard.hasURLs, let url = pasteboard.url, !url.isFileURL { payload = .url(url) }
        else if pasteboard.hasStrings, let text = pasteboard.string { payload = .text(text) }
        else { payload = nil }

        guard let payload else {
            note("clipboard not readable (prompt declined?)")
            return
        }
        do {
            if try await store.ingest(payload, method: .keyboard, policy: settings.policy) != nil {
                note("saved a copy")
                await reload()
            } else {
                note("clipboard was empty")
            }
        } catch {
            log.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            note("save failed")
        }
    }

    /// Status for the debug readout only. Never contains clipboard content.
    private func note(_ message: String) {
        #if DEBUG
        lastDebugMessage = "auto-capture: \(message)"
        #endif
    }

    private func refreshState() {
        if !hasFullAccess { state = .noFullAccess }
        else if isSecure { state = .secureField }
        else if store == nil { state = .storageUnavailable }
        else { state = items.isEmpty ? .empty : .ready }
    }

    /// Inserts the item's full text. The row only carries the preview, so the text is fetched now.
    func insert(_ item: ClipItemValue) async {
        guard !isSecure else { return }
        let text: String?
        if let t = item.text { text = t } else { text = try? await store?.item(id: item.id)?.text }
        if let text { actions.insert(text) }
    }

    #if DEBUG
    /// Device question 3: does UIPasteControl work in the keyboard? Records counts only.
    func handlePasteProbe(providers: [NSItemProvider]) async {
        let payloads = await ProviderIngest.payloads(from: providers)
        var chars = 0, images = 0
        for payload in payloads {
            switch payload {
            case .text(let t): chars += t.count
            case .url(let u): chars += u.absoluteString.count
            case .image: images += 1
            }
        }
        lastDebugMessage = "UIPasteControl delivered \(payloads.count) item(s): \(chars) chars, \(images) image(s)"
        if hasFullAccess, let store {
            for payload in payloads { _ = try? await store.ingest(payload, method: .keyboard) }
            await reload()
        }
    }
    #endif
}
