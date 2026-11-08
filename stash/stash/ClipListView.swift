import SwiftUI
import UniformTypeIdentifiers
import ClipKit

struct ClipListView: View {
    @Bindable var model: AppModel
    let lock: AppLock
    @State private var query = ""
    @State private var showingSettings = false
    @State private var showingIntro = false
    @Environment(\.scenePhase) private var scenePhase

    private var pinned: [ClipItemValue] { model.items.filter(\.isPinned) }
    private var recent: [ClipItemValue] { model.items.filter { !$0.isPinned } }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("ClipVault")
                .searchable(text: $query, prompt: "Search clips")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SavePasteButton(model: model)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack { SettingsView(model: model, lock: lock) }
                }
                .sheet(isPresented: $showingIntro) { OnboardingView { showingIntro = false } }
                .overlay(alignment: .bottom) { toast }
        }
        .task(id: query) { await model.reload(query: query) }
        // Sensitive items expire after 10 minutes; keep the visible list honest while the app is open.
        .task(id: query) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.reload(query: query)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.handleForeground() } }
        }
        .onAppear { Task { await model.handleForeground() } }
    }

    @ViewBuilder private var content: some View {
        if model.status == .storageUnavailable {
            ContentUnavailableView("Storage unavailable",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text("ClipVault could not open its shared storage. Check that the App Group is enabled for this build."))
        } else if model.items.isEmpty {
            VStack(spacing: 16) {
                if model.showClipboardHint { ClipboardHintBanner(model: model) }
                if query.isEmpty {
                    EmptyStateView { showingIntro = true }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .padding(.horizontal)
        } else {
            List {
                if model.showClipboardHint {
                    ClipboardHintBanner(model: model)
                        .listRowBackground(Color.clear)
                }
                if !pinned.isEmpty {
                    Section("Pinned") { rows(pinned) }
                }
                Section(pinned.isEmpty ? "" : "Recent") { rows(recent) }
            }
        }
    }

    private func rows(_ items: [ClipItemValue]) -> some View {
        ForEach(items) { item in
            ClipRowView(item: item, thumbnailURL: model.thumbnailURL(for: item))
                .contentShape(Rectangle())
                .onTapGesture { model.copy(item) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await model.delete(item, query: query) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await model.togglePin(item, query: query) }
                    } label: {
                        Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.orange)
                }
                .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") {
                    Task { await model.togglePin(item, query: query) }
                }
                .accessibilityAction(named: "Delete") {
                    Task { await model.delete(item, query: query) }
                }
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityHidden(true) // announced via UIAccessibility instead
        }
    }
}

/// The only way this app reads the pasteboard: a system paste control the user taps.
struct SavePasteButton: View {
    let model: AppModel

    var body: some View {
        PasteButton(supportedContentTypes: [.plainText, .url, .image]) { providers in
            Task { await model.save(providers: providers) }
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Save from clipboard")
    }
}

#Preview("With items") {
    ClipListView(model: .preview(), lock: .preview())
}

#Preview("Empty") {
    ClipListView(model: .preview(seed: false), lock: .preview())
}

#Preview("Storage unavailable") {
    ClipListView(model: AppModel(store: nil), lock: .preview())
}
