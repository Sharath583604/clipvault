import UIKit
import SwiftUI
import ClipKit
import os

/// Saves whatever the user shares (text, a URL or an image) into the shared ClipStore.
/// Nothing is read from the clipboard here: the content arrives through the share sheet.
final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private let log = Logger(subsystem: "com.sclera.clipvault.ShareExtension", category: "Share")

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareStatusView(model: model) { [weak self] in
            self?.finish()
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await save() }
    }

    private func save() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let payloads = await ProviderIngest.payloads(from: items)
        guard !payloads.isEmpty else {
            // Type names and counts only, never content, so this is safe to log.
            let described = items.map { item in
                (item.attachments ?? []).map { $0.registeredTypeIdentifiers.joined(separator: ",") }
                    .joined(separator: " | ")
                    + (item.attributedContentText == nil ? "" : " [item text]")
            }
            log.error("Nothing readable. items=\(items.count) types=\(described.joined(separator: " || "), privacy: .public)")
            model.state = .failed(String(localized: "There was nothing ClipVault can save here."))
            return
        }
        do {
            let store = try ClipStore.open(location: StorageLocation.appGroup(), onChange: WidgetRefresh.reload)
            let settings = ClipSettings()
            var saved = 0
            var lastSaved: ClipItemValue?
            for payload in payloads {
                if let item = try await store.ingest(payload, method: .share, policy: settings.policy) {
                    saved += 1
                    lastSaved = item
                }
            }
            guard saved > 0, let lastSaved else {
                model.state = .failed(String(localized: "That content could not be saved."))
                return
            }
            // Make the shared item the current clipboard too, so pasting anywhere gives it instead of
            // whatever was copied before. PasteboardWriter also marks this clipboard change as handled,
            // so the app and keyboard do not re-save the old copy on top of it.
            var copied = false
            if settings.copyAfterShare {
                copied = PasteboardWriter.write(lastSaved, blobURL: store.blobURL(for: lastSaved)) == .copied
            }
            model.state = .saved(copied: copied)
            try? await Task.sleep(for: .milliseconds(700))
            finish()
        } catch {
            log.error("Share save failed: \(error.localizedDescription, privacy: .public)")
            model.state = .failed(String(localized: "ClipVault could not open its storage."))
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@MainActor
@Observable
final class ShareModel {
    enum State: Equatable { case saving, saved(copied: Bool), failed(String) }
    var state: State = .saving
}

struct ShareStatusView: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch model.state {
            case .saving:
                ProgressView()
                Text("Saving to ClipVault…")
            case .saved(let copied):
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle).foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(copied ? "Saved and copied" : "Saved to ClipVault")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: close).buttonStyle(.borderedProminent)
            }
        }
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Saved") {
    ShareStatusView(model: { let m = ShareModel(); m.state = .saved(copied: true); return m }(), close: {})
}

#Preview("Failed") {
    ShareStatusView(model: { let m = ShareModel(); m.state = .failed("Nothing to save."); return m }(), close: {})
}
