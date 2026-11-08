import AppIntents

struct ClipVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: ["Save clipboard to \(.applicationName)",
                      "Save my clipboard in \(.applicationName)"],
            shortTitle: "Save Clipboard",
            systemImageName: "doc.on.clipboard")
        AppShortcut(
            intent: CopyItemIntent(),
            phrases: ["Copy a clip from \(.applicationName)",
                      "Copy from \(.applicationName)"],
            shortTitle: "Copy Clip",
            systemImageName: "doc.on.doc")
    }
}
