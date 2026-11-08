import Foundation

/// User settings shared by every target through App Group defaults.
public struct ClipSettings: Sendable {
    public static let retentionDaysKey = "retentionDays"
    public static let defaultRetentionDays = 30
    /// 0 means keep forever.
    public static let retentionOptions = [1, 7, 30, 90, 0]

    private let suiteName: String

    public init(suiteName: String = StorageLocation.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    // UserDefaults is not Sendable, so it is opened on demand instead of stored.
    private var defaults: UserDefaults { Self.sharedDefaults(suiteName: suiteName) }

    /// App Group defaults, or standard defaults if the group is unavailable (previews, tests).
    public static func sharedDefaults(suiteName: String = StorageLocation.appGroupIdentifier) -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public var retentionDays: Int {
        get {
            defaults.object(forKey: Self.retentionDaysKey) == nil
                ? Self.defaultRetentionDays
                : defaults.integer(forKey: Self.retentionDaysKey)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.retentionDaysKey) }
    }

    public static let lockEnabledKey = "lockEnabled"
    public static let autoSaveKey = "autoSaveOnOpen"
    public static let copyAfterShareKey = "copyAfterShare"

    /// After sharing to ClipVault, also put the shared item on the system clipboard so the next
    /// paste gives it. On by default.
    public var copyAfterShare: Bool {
        get { defaults.object(forKey: Self.copyAfterShareKey) == nil ? true : defaults.bool(forKey: Self.copyAfterShareKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.copyAfterShareKey) }
    }
    public static let keyboardAutoSaveKey = "keyboardAutoSave"
    public static let lastHandledChangeCountKey = "lastHandledPasteboardChangeCount"

    /// Whether the keyboard saves the clipboard when it appears or when the pasteboard changes
    /// while it is visible. On by default; needs Full Access. iOS may show its paste prompt.
    public var keyboardAutoSave: Bool {
        get { defaults.object(forKey: Self.keyboardAutoSaveKey) == nil ? true : defaults.bool(forKey: Self.keyboardAutoSaveKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.keyboardAutoSaveKey) }
    }

    /// Pasteboard `changeCount` last captured or written by any ClipVault process, so the app,
    /// keyboard and widget never save the same copy twice or re-save our own copy-back.
    public var lastHandledPasteboardChangeCount: Int {
        get { defaults.integer(forKey: Self.lastHandledChangeCountKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastHandledChangeCountKey) }
    }

    /// Opt-in: read the clipboard when the app opens. iOS asks permission per copy unless the user
    /// sets Settings > ClipVault > Paste from Other Apps to Allow. Off by default.
    public var autoSaveOnOpen: Bool {
        get { defaults.bool(forKey: Self.autoSaveKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.autoSaveKey) }
    }

    /// Whether the main app requires Face ID / passcode. Does not affect the keyboard or widget.
    public var lockEnabled: Bool {
        get { defaults.bool(forKey: Self.lockEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lockEnabledKey) }
    }

    public var policy: SensitivePolicy { SensitivePolicy(retentionDays: retentionDays) }
}
