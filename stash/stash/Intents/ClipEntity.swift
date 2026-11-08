import AppIntents
import ClipKit

/// A saved clip as Shortcuts sees it. Sensitive items appear with their masked preview.
struct ClipEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clip")
    static let defaultQuery = ClipEntityQuery()

    var id: UUID
    var preview: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(preview)")
    }

    init(_ item: ClipItemValue) {
        id = item.id
        preview = item.preview
    }
}

struct ClipEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ClipEntity] {
        let store = try IntentStore.open()
        var result: [ClipEntity] = []
        for id in identifiers {
            if let item = try await store.item(id: id) { result.append(ClipEntity(item)) }
        }
        return result
    }

    func entities(matching string: String) async throws -> [ClipEntity] {
        try await IntentStore.open().search(string, limit: 20).map(ClipEntity.init)
    }

    func suggestedEntities() async throws -> [ClipEntity] {
        try await IntentStore.open().recent(limit: 10).map(ClipEntity.init)
    }
}

nonisolated enum IntentStore {
    static func open() throws -> ClipStore {
        try ClipStore.open(location: StorageLocation.appGroup(), onChange: WidgetRefresh.reload)
    }
}
