/// # Item Client
/// @topic dependency
///
/// Dependency client for item CRUD operations. Demonstrates the client pattern:
/// a struct with closure properties, registered via `DependencyKey`.
///
/// ## Key Rules
/// - Model as struct with closure properties — not a protocol
/// - `liveValue` uses an in-memory actor (no real persistence in the reference app)
/// - `testValue` uses `unimplemented()` to catch untested code paths
/// - `previewValue` returns safe static data for SwiftUI previews
/// - Access via `@Dependency(\.itemClient)` inside `@Reducer` structs only

import ComposableArchitecture
import Foundation
import IdentifiedCollections

// MARK: - Client Definition

public struct ItemClient {
    var delete: @Sendable (UUID) async throws -> Void
    var fetch: @Sendable (UUID) async throws -> Item
    var fetchAll: @Sendable () async throws -> IdentifiedArrayOf<Item>
    var save: @Sendable (Item) async throws -> Item
}

// MARK: - In-Memory Storage Actor

/// Actor-isolated in-memory storage used by `liveValue`.
/// A real app would use SQLiteData, Core Data, or a network layer.
private actor ItemStorage {
    var items: IdentifiedArrayOf<Item> = Item.samples

    func delete(id: UUID) throws {
        guard items[id: id] != nil else {
            throw ItemClientError.notFound
        }
        items.remove(id: id)
    }

    func fetch(id: UUID) throws -> Item {
        guard let item = items[id: id] else {
            throw ItemClientError.notFound
        }
        return item
    }

    func fetchAll() -> IdentifiedArrayOf<Item> {
        items
    }

    func save(item: Item) -> Item {
        items[id: item.id] = item
        return item
    }
}

public enum ItemClientError: Error, Equatable, Sendable {
    case notFound
}

// MARK: - Dependency Registration

extension ItemClient: DependencyKey {
    /// Live implementation — uses actor-isolated in-memory storage
    public static let liveValue: ItemClient = {
        let storage = ItemStorage()
        return ItemClient(
            delete: { id in
                try await storage.delete(id: id)
            },
            fetch: { id in
                try await storage.fetch(id: id)
            },
            fetchAll: {
                await storage.fetchAll()
            },
            save: { item in
                await storage.save(item: item)
            }
        )
    }()

    /// Test implementation — `unimplemented()` forces tests to explicitly
    /// override only the dependencies they need
    public static let testValue = ItemClient(
        delete: unimplemented("ItemClient.delete"),
        fetch: unimplemented("ItemClient.fetch"),
        fetchAll: unimplemented("ItemClient.fetchAll"),
        save: unimplemented("ItemClient.save")
    )

    /// Preview implementation — returns safe static data for SwiftUI previews
    public static let previewValue = ItemClient(
        delete: { _ in },
        fetch: { _ in .preview },
        fetchAll: { .samples },
        save: { item in item }
    )
}

// MARK: - Dependency Values Extension

extension DependencyValues {
    public var itemClient: ItemClient {
        get { self[ItemClient.self] }
        set { self[ItemClient.self] = newValue }
    }
}
