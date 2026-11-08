import Foundation

/// Remembers which clip a widget button just copied, so the widget can show "Copied" feedback.
/// Stored in App Group defaults because the button's intent and the widget timeline may run in
/// different processes.
public struct WidgetCopyState: Sendable {
    private static let idKey = "widgetLastCopiedID"
    private static let timeKey = "widgetLastCopiedAt"
    private let suiteName: String

    public init(suiteName: String = StorageLocation.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { ClipSettings.sharedDefaults(suiteName: suiteName) }

    public func record(id: UUID, now: Date = Date()) {
        defaults.set(id.uuidString, forKey: Self.idKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.timeKey)
    }

    /// The clip copied within the last `window` seconds, if any.
    public func recentlyCopiedID(now: Date = Date(), within window: TimeInterval = 60) -> UUID? {
        guard let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw) else { return nil }
        let at = Date(timeIntervalSince1970: defaults.double(forKey: Self.timeKey))
        return now.timeIntervalSince(at) <= window && now >= at ? id : nil
    }
}
