import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let points: [LocalizedStringKey]

    static let all: [OnboardingPage] = [
        OnboardingPage(
            symbol: "doc.on.clipboard",
            title: "Your clipboard, kept on purpose",
            message: "iOS does not let any app watch the clipboard in the background, and ClipVault does not try to. It saves what you choose to save, plus, if you allow it, the clipboard when the app or keyboard opens.",
            points: ["Everything stays on this device.",
                     "No accounts, no analytics, no network requests."]),
        OnboardingPage(
            symbol: "square.and.arrow.down",
            title: "Three ways to save",
            message: "Pick whichever fits the moment.",
            points: ["Paste button: tap it in ClipVault to save what you just copied. iOS lets this button read one item without asking.",
                     "Share sheet: choose Save to ClipVault from any app.",
                     "Optional: turn on Save clipboard when ClipVault opens in Settings. It works only while the app opens, because iOS never reports copies made elsewhere.",
                     "Shortcuts and the Action button: run Save Clipboard to ClipVault. iOS may ask your permission to paste the first time."]),
        OnboardingPage(
            symbol: "keyboard",
            title: "Paste from anywhere",
            message: "Add the ClipVault keyboard in Settings → General → Keyboard → Keyboards, then switch to it with the globe key.",
            points: ["To show your history, the keyboard needs Allow Full Access. That is how iOS lets a keyboard read ClipVault's saved items. ClipVault never sends anything off your device.",
                     "Without Full Access the keyboard still types space, delete and return, but cannot show your history.",
                     "With Full Access on, the keyboard also saves what you copy while it is open. iOS keeps only the latest copy, so copies made while the keyboard is closed are lost except the last one.",
                     "The widget also lets you tap a clip to copy it."]),
        OnboardingPage(
            symbol: "lock.shield",
            title: "Private by design",
            message: "One-time codes and card-like numbers are masked and deleted after 10 minutes.",
            points: ["Swipe to delete anything, or clear all history in Settings.",
                     "Turn on Face ID in Settings to lock the app. It does not lock the keyboard, widget or Shortcuts."]),
    ]
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var index = 0
    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    OnboardingPageView(page: page).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(index == pages.count - 1 ? "Get started" : "Next") {
                if index == pages.count - 1 { onFinish() } else { withAnimation { index += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()

            Button("Skip", action: onFinish)
                .font(.footnote)
                .padding(.bottom, 12)
                .opacity(index == pages.count - 1 ? 0 : 1)
                .accessibilityHidden(index == pages.count - 1)
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: page.symbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(page.message).font(.body)
                ForEach(Array(page.points.enumerated()), id: \.offset) { _, point in
                    Label {
                        Text(point).font(.callout)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Onboarding") { OnboardingView(onFinish: {}) }
#Preview("Large type") { OnboardingView(onFinish: {}).dynamicTypeSize(.accessibility3) }
