#if canImport(UIKit)
import UIKit

/// Writes a clip back to the system pasteboard. Writing never raises the paste alert.
/// Used by the app, App Intents and the widget so they all behave the same way.
@MainActor
public enum PasteboardWriter {
    public enum Outcome: Sendable { case copied, unavailable }

    /// `item` must carry its full text (use `ClipStore.item(id:)`). `blobURL` is needed for images.
    @discardableResult
    public static func write(_ item: ClipItemValue, blobURL: URL?,
                             pasteboard: UIPasteboard = .general) -> Outcome {
        let outcome = writeContents(item, blobURL: blobURL, pasteboard: pasteboard)
        if outcome == .copied {
            // Our own copy-back must not be re-captured by the app or keyboard as a new copy.
            ClipSettings().lastHandledPasteboardChangeCount = pasteboard.changeCount
        }
        return outcome
    }

    private static func writeContents(_ item: ClipItemValue, blobURL: URL?,
                                      pasteboard: UIPasteboard) -> Outcome {
        switch item.kind {
        case .text, .url, .file:
            guard let text = item.text else { return .unavailable }
            if item.isSensitive {
                // Keep sensitive values off Universal Clipboard and let them lapse quickly.
                pasteboard.setItems([["public.utf8-plain-text": text]],
                                    options: [.localOnly: true,
                                              .expirationDate: Date().addingTimeInterval(120)])
            } else {
                pasteboard.string = text
            }
            return .copied
        case .image:
            guard let blobURL, let image = UIImage(contentsOfFile: blobURL.path) else { return .unavailable }
            pasteboard.image = image
            return .copied
        }
    }
}
#endif
