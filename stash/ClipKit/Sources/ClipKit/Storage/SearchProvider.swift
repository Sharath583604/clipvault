import Foundation

/// Search seam. Substring today; a semantic (NaturalLanguage embedding) provider can
/// conform later without touching `ClipStore` callers.
public protocol SearchProvider: Sendable {
    func rank(query: String, in items: [ClipItemValue]) -> [ClipItemValue]
}

public struct SubstringSearchProvider: SearchProvider {
    public init() {}

    public func rank(query: String, in items: [ClipItemValue]) -> [ClipItemValue] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            // Sensitive items are searchable by their masked preview only.
            let haystack = item.isSensitive ? item.preview : (item.text ?? item.preview)
            return haystack.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
