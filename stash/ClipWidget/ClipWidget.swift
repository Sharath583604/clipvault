import WidgetKit
import SwiftUI
import AppIntents
import ClipKit
import os

// MARK: - Timeline

struct ClipEntry: TimelineEntry {
    let date: Date
    let items: [ClipItemValue]
    let storageAvailable: Bool
    /// The row the user just tapped, shown with a "Copied" check for a short time.
    var copiedID: UUID? = nil
}

/// No user configuration; this exists so the provider can load data with async/await.
struct ClipWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Recent clips"
    static let isDiscoverable = false
}

struct ClipProvider: AppIntentTimelineProvider {
    private static let log = Logger(subsystem: "com.shar.clipvault.ClipWidget", category: "Timeline")

    func placeholder(in context: Context) -> ClipEntry {
        ClipEntry(date: .now, items: ClipItemValue.widgetSamples, storageAvailable: true)
    }

    func snapshot(for configuration: ClipWidgetConfiguration, in context: Context) async -> ClipEntry {
        context.isPreview ? placeholder(in: context) : await load(at: .now)
    }

    /// Entry 1 is now (with a "Copied" check if a row was just tapped); entry 2 is 5 minutes
    /// later without the check, which is the minimum spacing. After that, no refresh for 30
    /// minutes. The app reloads timelines after every save, so new copies show up immediately
    /// without spending refresh budget.
    func timeline(for configuration: ClipWidgetConfiguration, in context: Context) async -> Timeline<ClipEntry> {
        let now = Date.now
        let first = await load(at: now)
        var entries = [first]
        if first.copiedID != nil {
            let cleared = ClipEntry(date: now.addingTimeInterval(5 * 60), items: first.items,
                                storageAvailable: first.storageAvailable, copiedID: nil)
            entries.append(cleared)
        }
        let last = entries.last?.date ?? now
        return Timeline(entries: entries, policy: .after(last.addingTimeInterval(30 * 60)))
    }

    private func load(at date: Date) async -> ClipEntry {
        do {
            let store = try ClipStore.open(location: StorageLocation.appGroup())
            let items = try await store.widgetItems(limit: 2)
            return ClipEntry(date: date, items: items, storageAvailable: true,
                             copiedID: WidgetCopyState().recentlyCopiedID(now: date))
        } catch {
            Self.log.error("Widget load failed: \(error.localizedDescription, privacy: .public)")
            return ClipEntry(date: date, items: [], storageAvailable: false)
        }
    }
}

// MARK: - Widget

struct ClipWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ClipWidget", intent: ClipWidgetConfiguration.self,
                               provider: ClipProvider()) { entry in
            ClipWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Recent clips")
        .description("Your two latest copies. Tap one to copy it, then paste anywhere.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClipWidgetView: View {
    let entry: ClipEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.storageAvailable {
            message(symbol: "exclamationmark.triangle", text: "Open ClipVault once to set up.")
        } else if entry.items.isEmpty {
            message(symbol: "doc.on.clipboard", text: "No clips yet. Save one in ClipVault.")
        } else {
            // Always two equal-height rows, so a single clip does not stretch to fill the widget.
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    if index < entry.items.count {
                        let item = entry.items[index]
                        Button(intent: CopyClipIntent(itemID: item.id.uuidString)) {
                            ClipWidgetRow(item: item, copied: entry.copiedID == item.id,
                                          compact: family == .systemSmall)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func message(symbol: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipWidgetRow: View {
    let item: ClipItemValue
    let copied: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: copied ? "checkmark.circle.fill" : (item.kind == .url ? "link" : "doc.on.doc"))
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(copied ? Color.green : Color.accentColor)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(copied ? String(localized: "Copied") : item.preview)
                .font(compact ? .caption : .footnote)
                .fontWeight(copied ? .semibold : .regular)
                .lineLimit(compact ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.preview)
        .accessibilityHint(copied ? "Copied" : "Copies this clip")
    }
}

// MARK: - Previews

extension ClipItemValue {
    static var widgetSamples: [ClipItemValue] {
        func make(_ text: String, kind: ClipKind = .text) -> ClipItemValue {
            ClipItemValue(id: UUID(), createdAt: .now, kind: kind, text: nil, preview: text, blobPath: nil,
                          contentHash: text, isPinned: false, expiresAt: nil, isSensitive: false,
                          captureMethod: .share)
        }
        return [make("Meeting notes: ship the keyboard on Friday and then start on widgets"),
                make("https://developer.apple.com/documentation/widgetkit", kind: .url)]
    }
}

#Preview("Small", as: .systemSmall) {
    ClipWidget()
} timeline: {
    ClipEntry(date: .now, items: ClipItemValue.widgetSamples, storageAvailable: true)
    ClipEntry(date: .now, items: ClipItemValue.widgetSamples, storageAvailable: true,
              copiedID: ClipItemValue.widgetSamples[0].id)
    ClipEntry(date: .now, items: Array(ClipItemValue.widgetSamples.prefix(1)), storageAvailable: true)
    ClipEntry(date: .now, items: [], storageAvailable: true)
    ClipEntry(date: .now, items: [], storageAvailable: false)
}

#Preview("Medium", as: .systemMedium) {
    ClipWidget()
} timeline: {
    ClipEntry(date: .now, items: ClipItemValue.widgetSamples, storageAvailable: true)
}
