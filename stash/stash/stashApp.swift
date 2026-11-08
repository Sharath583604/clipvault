import SwiftUI
import ClipKit

@main
struct ClipVaultApp: App {
    @State private var model = AppModel.live()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, lock: lock)
        }
    }
}
