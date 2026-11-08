import Foundation
import UniformTypeIdentifiers

/// What the user handed us, before it becomes a clip.
public enum IngestPayload: Sendable, Equatable {
    case text(String)
    case url(URL)
    case image(Data)
}

/// Turns `NSItemProvider`s (from PasteButton or the share sheet) into payloads. Main-actor
/// only because providers are not Sendable; only Sendable values leave the callbacks.
@MainActor
public enum ProviderIngest {
    /// Reads whole share-sheet items. Attachments are tried first; if an item has none that we can
    /// read, text placed directly on the item (`attributedContentText`) is used instead, because
    /// some apps share that way.
    public static func payloads(from items: [NSExtensionItem]) async -> [IngestPayload] {
        var result: [IngestPayload] = []
        for item in items {
            let found = await payloads(from: item.attachments ?? [])
            if !found.isEmpty {
                result += found
            } else if let text = item.attributedContentText?.string
                        .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                result.append(.text(text))
            }
        }
        return result
    }

    /// One payload per provider. Preference: web URL, then text, then image.
    public static func payloads(from providers: [NSItemProvider]) async -> [IngestPayload] {
        var result: [IngestPayload] = []
        for provider in providers {
            if let payload = await payload(from: provider) { result.append(payload) }
        }
        return result
    }

    private static func payload(from provider: NSItemProvider) async -> IngestPayload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider), !url.isFileURL {
            return .url(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(provider), !text.isEmpty {
            return .text(text)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadImageData(provider) {
            return .image(data)
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }

    /// Tries the simple string read first, then loads each registered text type directly, since
    /// many apps register plain text as a generic type or as raw data that the simple read rejects.
    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let simple: String? = await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: String.self) { text, _ in cont.resume(returning: text) }
        }
        if let simple, !simple.isEmpty { return simple }

        for identifier in provider.registeredTypeIdentifiers {
            guard UTType(identifier)?.conforms(to: .text) == true else { continue }
            let text: String? = await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                    switch item {
                    case let string as String: cont.resume(returning: string)
                    case let attributed as NSAttributedString: cont.resume(returning: attributed.string)
                    case let data as Data:
                        cont.resume(returning: String(data: data, encoding: .utf8)
                                    ?? String(data: data, encoding: .utf16))
                    default: cont.resume(returning: nil)
                    }
                }
            }
            if let text, !text.isEmpty { return text }
        }
        return nil
    }

    /// Apps usually register a concrete image type (jpeg, png, heic) rather than `public.image`, so
    /// try those registered types first and the generic type last.
    private static func loadImageData(_ provider: NSItemProvider) async -> Data? {
        let concrete = provider.registeredTypeIdentifiers.filter {
            $0 != UTType.image.identifier && UTType($0)?.conforms(to: .image) == true
        }
        for identifier in concrete + [UTType.image.identifier] {
            let data: Data? = await withCheckedContinuation { cont in
                _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
            if let data, !data.isEmpty { return data }
        }
        return nil
    }
}
