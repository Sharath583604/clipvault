import AppIntents
import ClipKit

/// Puts a saved clip back on the clipboard so the next "Paste" inserts it.
struct CopyItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Clip from ClipVault"
    static let description = IntentDescription(
        "Copies a saved ClipVault item back to the clipboard.", categoryName: "Clipboard")
    static let openAppWhenRun = false

    @Parameter(title: "Clip")
    var item: ClipEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copy \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentStore.open()
        guard let clip = try await store.item(id: item.id) else {
            return .result(dialog: "That clip is no longer saved.")
        }
        let outcome = PasteboardWriter.write(clip, blobURL: store.blobURL(for: clip))
        return .result(dialog: outcome == .copied ? "Copied." : "That clip is no longer available.")
    }
}
