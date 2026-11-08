import SwiftUI

struct EmptyStateView: View {
    let showIntro: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No clips yet", systemImage: "doc.on.clipboard")
        } description: {
            Text("Copy something, then tap the Paste button above to save it. You can also use Share → Save to ClipVault from any app.")
        } actions: {
            Button("How ClipVault works", action: showIntro)
        }
    }
}

#Preview { EmptyStateView(showIntro: {}) }
