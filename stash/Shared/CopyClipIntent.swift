import AppIntents
import ClipKit

/// Runs when a widget row is tapped. This file is compiled into BOTH the app and the widget
/// extension on purpose: when the intent also exists in the app target, iOS can run it in the
/// app's process in the background, which is a more reliable place to write the pasteboard than
/// the short-lived widget process. Not exposed in Shortcuts (the app's `CopyItemIntent` is).
///
/// Whether iOS picks the app process, and whether the pasteboard write sticks, is on the README's
/// device checklist.
struct CopyClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy clip"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Clip ID") var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let store = try ClipStore.open(location: StorageLocation.appGroup())
        guard let clip = try await store.item(id: id) else { return .result() }
        if PasteboardWriter.write(clip, blobURL: store.blobURL(for: clip)) == .copied {
            // Lets the widget show "Copied" on the row that was tapped.
            WidgetCopyState().record(id: id)
        }
        return .result()
    }
}
