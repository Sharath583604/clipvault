import AppIntents
import UIKit
import ClipKit

/// Saves the clipboard into ClipVault. Runs in the background (no app launch).
///
/// Whether reading `UIPasteboard` from here shows the system paste prompt depends on how the
/// intent is started (Action button, Shortcut, Siri); that is device question 2 in the README.
/// To avoid the prompt entirely, a Shortcut can pass its own "Get Clipboard" result in `content`.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to ClipVault"
    static let description = IntentDescription(
        "Saves the current clipboard text, link or image into your ClipVault history.",
        categoryName: "Clipboard")
    static let openAppWhenRun = false

    @Parameter(title: "Content",
               description: "Optional. Leave empty to read the clipboard.")
    var content: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let payload: IngestPayload?
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload = .text(content)
        } else {
            payload = Self.readPasteboard()
        }
        guard let payload else {
            return .result(dialog: "The clipboard is empty, so nothing was saved.")
        }
        let store = try IntentStore.open()
        let saved = try await store.ingest(payload, method: .intent, policy: ClipSettings().policy)
        return .result(dialog: saved == nil ? "That content could not be saved." : "Saved to ClipVault.")
    }

    @MainActor
    private static func readPasteboard() -> IngestPayload? {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasURLs, let url = pasteboard.url, !url.isFileURL { return .url(url) }
        if pasteboard.hasStrings, let text = pasteboard.string { return .text(text) }
        if pasteboard.hasImages, let data = pasteboard.image?.pngData() { return .image(data) }
        return nil
    }
}
