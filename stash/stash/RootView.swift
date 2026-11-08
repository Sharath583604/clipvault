import SwiftUI
import ClipKit

/// Hosts the list, the first-run intro and the optional lock cover.
struct RootView: View {
    let model: AppModel
    let lock: AppLock
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    private var coverVisible: Bool {
        lock.isEnabled && (lock.isLocked || scenePhase != .active)
    }

    var body: some View {
        ZStack {
            ClipListView(model: model, lock: lock)
                .accessibilityHidden(coverVisible)
            if coverVisible {
                LockCoverView(lock: lock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: coverVisible)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
            unlockIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.appDidEnterBackground()
            case .active: unlockIfNeeded()
            default: break
            }
        }
    }

    private func unlockIfNeeded() {
        guard lock.isLocked else { return }
        Task { await lock.unlock(reason: String(localized: "Unlock ClipVault to view your saved clips.")) }
    }
}

/// Opaque cover shown while locked and while the app is inactive (hides the app switcher snapshot).
struct LockCoverView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("ClipVault is locked").font(.title3.weight(.semibold))
            if lock.isLocked {
                Button("Unlock") {
                    Task { await lock.unlock(reason: String(localized: "Unlock ClipVault to view your saved clips.")) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(lock.isAuthenticating)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview("Locked") {
    LockCoverView(lock: AppLock(authenticator: PreviewAuthenticator(), settings: ClipSettings(suiteName: "preview")))
}
