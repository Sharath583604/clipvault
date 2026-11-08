import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("What ClipVault stores",
                        "Items you save by tapping Paste, using the Share sheet, or running a Shortcut. If you leave these options on, it also saves the clipboard when the app opens and when the ClipVault keyboard is open (the keyboard needs Full Access). You can turn both off in Settings. ClipVault never watches your clipboard while it is closed or in the background.")
                section("Where it is stored",
                        "On this device only, in storage shared between the app, its keyboard, its share extension and its widget. Nothing is sent to any server. ClipVault contains no analytics or advertising code and makes no network requests.")
                section("Sensitive items",
                        "One-time codes and card-like numbers are masked in lists and deleted automatically after 10 minutes.")
                section("Keyboard and Full Access",
                        "The ClipVault keyboard can show your saved items only if you turn on Allow Full Access, because iOS blocks shared storage otherwise. Full Access lets a keyboard use the network in general; ClipVault does not. Without it the keyboard still works, but cannot show your history.")
                section("Your control",
                        "Swipe to delete any item, choose how long history is kept, or clear everything in Settings. Deleting the app removes all saved data.")
            }
            .padding()
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(body).font(.body)
        }
    }
}

#Preview { NavigationStack { PrivacyPolicyView() } }
