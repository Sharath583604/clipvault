import SwiftUI
import ClipKit

struct ClipRowView: View {
    let item: ClipItemValue
    let thumbnailURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.body)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if item.isPinned { Image(systemName: "pin.fill").accessibilityHidden(true) }
                    if item.isSensitive, let expiry = item.expiresAt {
                        Image(systemName: "lock.fill").accessibilityHidden(true)
                        Text("Expires \(expiry, style: .relative)")
                    } else {
                        Text(item.createdAt, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to copy")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .image, let thumbnailURL {
            ThumbnailView(url: thumbnailURL)
        } else {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        if item.isSensitive { return "lock.shield" }
        switch item.kind {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var kindName: String {
        if item.isSensitive { return String(localized: "Sensitive item") }
        switch item.kind {
        case .text: return String(localized: "Text")
        case .url: return String(localized: "Link")
        case .image: return String(localized: "Image")
        case .file: return String(localized: "File")
        }
    }

    private var accessibilityLabel: String {
        var parts = [kindName, item.preview]
        if item.isPinned { parts.append(String(localized: "Pinned")) }
        return parts.joined(separator: ", ")
    }
}

/// Decodes a small thumbnail off the main thread. Main app only; the keyboard never shows images.
struct ThumbnailView: View {
    let url: URL
    @State private var image: CGImage?
    @ScaledMetric(relativeTo: .body) private var size = 48

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: url) {
            let target = url
            let pixels = 200
            image = await Task.detached { ImageIngest.thumbnail(at: target, maxPixel: pixels) }.value
        }
    }
}

#Preview("Rows") {
    List {
        ForEach(ClipItemValue.samples) { ClipRowView(item: $0, thumbnailURL: nil) }
    }
}

#Preview("Large type") {
    List {
        ForEach(ClipItemValue.samples) { ClipRowView(item: $0, thumbnailURL: nil) }
    }
    .dynamicTypeSize(.accessibility3)
}
