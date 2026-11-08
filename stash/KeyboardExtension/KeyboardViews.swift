import SwiftUI
import UIKit
import ClipKit

struct KeyboardRootView: View {
    let model: KeyboardModel
    /// Controller that owns the globe key. Nil in previews.
    let inputController: UIInputViewController?

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.hasFullAccess && !model.isSecure { AutoSaveRow(model: model) }
            #if DEBUG
            DebugReadout(model: model)
            #endif
            Divider()
            KeyBar(model: model, inputController: inputController)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .noFullAccess: FullAccessOffView()
        case .secureField:
            MessageView(symbol: "lock.fill", title: "Secure field",
                        message: "ClipVault items are hidden while you type in a secure field.")
        case .storageUnavailable:
            MessageView(symbol: "exclamationmark.triangle", title: "Storage unavailable",
                        message: "ClipVault could not open its shared storage. Open the ClipVault app once, then try again.")
        case .empty:
            MessageView(symbol: "doc.on.clipboard", title: "Nothing saved yet",
                        message: "Save items from the ClipVault app or the Share sheet and they appear here.")
        case .ready: ItemList(model: model)
        }
    }
}

/// One slim line so auto-saving can be switched off without leaving the app being typed in.
struct AutoSaveRow: View {
    let model: KeyboardModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.autoSave }, set: { model.setAutoSave($0) })) {
            Text("Save my copies automatically")
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .accessibilityHint("When on, ClipVault saves what you copy while this keyboard is open")
    }
}

struct ItemList: View {
    let model: KeyboardModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.items) { item in
                    Button { Task { await model.insert(item) } } label: {
                        KeyboardRow(item: item)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 44)
                }
            }
        }
    }
}

struct KeyboardRow: View {
    let item: ClipItemValue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(item.preview)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isPinned ? "\(item.preview), pinned" : item.preview)
        .accessibilityHint("Inserts into the text field")
        .accessibilityAddTraits(.isButton)
    }

    private var symbol: String {
        if item.isSensitive { return "lock.fill" }
        if item.isPinned { return "pin.fill" }
        return item.kind == .url ? "link" : "text.alignleft"
    }
}

struct FullAccessOffView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "lock.open.trianglebadge.exclamationmark")
                    .font(.title2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Full Access is off").font(.headline)
                Text("iOS only lets a keyboard read ClipVault's saved history when Full Access is on. Without it this keyboard can still type space, delete and return, but it cannot show your items.")
                    .font(.footnote).multilineTextAlignment(.center)
                Text("To turn it on: Settings → General → Keyboard → Keyboards → ClipVault → Allow Full Access. ClipVault never sends anything off your device.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct MessageView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

/// Always shown, including with Full Access off: next keyboard, space, delete, return.
struct KeyBar: View {
    let model: KeyboardModel
    let inputController: UIInputViewController?

    var body: some View {
        HStack(spacing: 6) {
            NextKeyboardButton(controller: inputController)
                .frame(width: 48, height: 40)
            key("space") { model.actions.insert(" ") }
            key(systemImage: "delete.left", label: "Delete") { model.actions.deleteBackward() }
                .frame(width: 56)
            key(systemImage: "return", label: "Return") { model.actions.returnKey() }
                .frame(width: 56)
        }
        .padding(6)
    }

    private func key(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(KeyStyle())
    }

    private func key(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(KeyStyle())
        .accessibilityLabel(label)
    }
}

struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Color(uiColor: .systemGray3) : Color(uiColor: .systemBackground),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The globe key. `handleInputModeList` needs the originating UIEvent, so this must be a
/// real UIButton wired to the controller rather than a SwiftUI Button.
struct NextKeyboardButton: UIViewRepresentable {
    let controller: UIInputViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 6
        button.accessibilityLabel = String(localized: "Next keyboard")
        if let controller {
            button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                             for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

#if DEBUG
/// Debug-only: Full Access state, row count and memory, refreshed every second, plus a
/// UIPasteControl probe for device question 3.
struct DebugReadout: View {
    let model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("fullAccess \(model.hasFullAccess ? "on" : "off") · rows \(model.items.count) · \(MemoryFootprint.megabytes(MemoryFootprint.currentBytes())) used · \(MemoryFootprint.megabytes(MemoryFootprint.availableBytes())) free")
            }
            HStack {
                PasteProbe { providers in Task { await model.handlePasteProbe(providers: providers) } }
                    .frame(width: 44, height: 28)
                Text(model.lastDebugMessage).lineLimit(2)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}

/// UIPasteControl wrapper. Pasting must go through a UIPasteConfigurationSupporting target.
struct PasteProbe: UIViewRepresentable {
    let onPaste: ([NSItemProvider]) -> Void

    final class Target: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(acceptableTypeIdentifiers: ["public.text", "public.url"])
        var onPaste: ([NSItemProvider]) -> Void = { _ in }
        func paste(itemProviders: [NSItemProvider]) { onPaste(itemProviders) }
    }

    func makeCoordinator() -> Target { Target() }

    func makeUIView(context: Context) -> UIPasteControl {
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconOnly
        let control = UIPasteControl(configuration: config)
        context.coordinator.onPaste = onPaste
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }
}
#endif

// MARK: - Previews

#Preview("Ready") {
    KeyboardRootView(model: KeyboardModel(previewState: .ready, items: [
        ClipItemValue(id: UUID(), createdAt: .now, kind: .url, text: nil, preview: "https://developer.apple.com",
                      blobPath: nil, contentHash: "a", isPinned: true, expiresAt: nil, isSensitive: false, captureMethod: .share),
        ClipItemValue(id: UUID(), createdAt: .now, kind: .text, text: nil, preview: "Meeting notes: ship M3 on Friday",
                      blobPath: nil, contentHash: "b", isPinned: false, expiresAt: nil, isSensitive: false, captureMethod: .share),
        ClipItemValue(id: UUID(), createdAt: .now, kind: .text, text: nil, preview: "••••••",
                      blobPath: nil, contentHash: "c", isPinned: false, expiresAt: .now, isSensitive: true, captureMethod: .share),
    ]), inputController: nil)
    .frame(height: 260)
}

#Preview("Full Access off") {
    KeyboardRootView(model: KeyboardModel(previewState: .noFullAccess), inputController: nil).frame(height: 260)
}

#Preview("Secure field") {
    KeyboardRootView(model: KeyboardModel(previewState: .secureField), inputController: nil).frame(height: 260)
}

#Preview("Empty") {
    KeyboardRootView(model: KeyboardModel(previewState: .empty), inputController: nil).frame(height: 260)
}

#Preview("Large type") {
    KeyboardRootView(model: KeyboardModel(previewState: .noFullAccess), inputController: nil)
        .frame(height: 260).dynamicTypeSize(.accessibility2)
}
