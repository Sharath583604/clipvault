import SwiftUI
import ClipKit

struct SettingsView: View {
    let model: AppModel
    let lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ClipSettings.retentionDaysKey, store: ClipSettings.sharedDefaults())
    private var retentionDays = ClipSettings.defaultRetentionDays
    @State private var confirmingClear = false
    @AppStorage(ClipSettings.autoSaveKey, store: ClipSettings.sharedDefaults())
    private var autoSaveOnOpen = false
    @Environment(\.openURL) private var openURL
    @AppStorage(ClipSettings.copyAfterShareKey, store: ClipSettings.sharedDefaults())
    private var copyAfterShare = true
    @AppStorage(ClipSettings.keyboardAutoSaveKey, store: ClipSettings.sharedDefaults())
    private var keyboardAutoSave = true
    @State private var lockFailed = false

    var body: some View {
        Form {
            Section {
                Picker("Keep clips for", selection: $retentionDays) {
                    ForEach(ClipSettings.retentionOptions, id: \.self) { days in
                        Text(label(for: days)).tag(days)
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Applies to clips saved from now on. Pinned clips are kept. One-time codes and card numbers always expire after 10 minutes.")
            }

            Section {
                Toggle("Save clipboard when ClipVault opens", isOn: $autoSaveOnOpen)
                Toggle("Save copies when the keyboard opens", isOn: $keyboardAutoSave)
                Toggle("Copy shared items to the clipboard", isOn: $copyAfterShare)
                Button("Open iOS Settings for ClipVault") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Capture")
            } footer: {
                Text("iOS never tells apps when you copy, so copies are saved only while ClipVault or its keyboard is open, and only the latest copy survives in between. Sharing to ClipVault also copies the shared item, so the next paste gives it. The keyboard needs Allow Full Access. iOS may ask permission to paste unless you set Paste from Other Apps to Allow in ClipVault's iOS settings.")
            }

            Section {
                Toggle("Require Face ID", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { wantsOn in
                        if wantsOn {
                            Task {
                                let ok = await lock.enable(reason: String(localized: "Confirm to turn on the ClipVault lock."))
                                lockFailed = !ok
                            }
                        } else {
                            lock.disable()
                            lockFailed = false
                        }
                    }))
                    .disabled(!lock.canAuthenticate && !lock.isEnabled)
            } header: {
                Text("Security")
            } footer: {
                if !lock.canAuthenticate && !lock.isEnabled {
                    Text("Set up Face ID or a device passcode to use this.")
                } else if lockFailed {
                    Text("Authentication did not succeed, so the lock was not turned on.")
                } else {
                    Text("Locks this app when it opens or returns from the background. The keyboard, widget and Shortcuts still work without unlocking, so keep sensitive items short-lived.")
                }
            }

            Section("Privacy") {
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
                Button("Clear all history", role: .destructive) { confirmingClear = true }
                    .confirmationDialog("Delete every saved clip?", isPresented: $confirmingClear,
                                        titleVisibility: .visible) {
                        Button("Delete all", role: .destructive) { Task { await model.clearAll() } }
                    } message: {
                        Text("Pinned clips are deleted too. This cannot be undone.")
                    }
            }

            Section("Help") {
                NavigationLink("How ClipVault works") { OnboardingView(onFinish: {}) }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func label(for days: Int) -> String {
        switch days {
        case 0: String(localized: "Forever")
        case 1: String(localized: "1 day")
        default: String(localized: "\(days) days")
        }
    }
}

#Preview {
    NavigationStack { SettingsView(model: .preview(seed: false), lock: .preview()) }
}
