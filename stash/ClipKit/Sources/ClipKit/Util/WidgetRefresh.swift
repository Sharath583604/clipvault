import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum WidgetRefresh {
    /// Asks WidgetKit to rebuild timelines. Call after saves; reloads requested by the
    /// foreground app or an extension that just ran are the cheap ones against the budget.
    @Sendable public static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
