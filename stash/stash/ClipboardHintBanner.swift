import SwiftUI

/// Shown in the foreground when the pasteboard changed. The paste control inside is what
/// grants one-time read access, so tapping it does not raise the system paste alert.
struct ClipboardHintBanner: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New item on clipboard", systemImage: "doc.on.clipboard")
                .font(.headline)
            Text("Tap Paste to save it to ClipVault. ClipVault never reads the clipboard on its own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                SavePasteButton(model: model)
                Spacer()
                Button("Dismiss") { model.dismissClipboardHint() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ClipboardHintBanner(model: .preview(seed: false)).padding()
}
