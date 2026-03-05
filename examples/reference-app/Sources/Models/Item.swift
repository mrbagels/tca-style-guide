/// # Item Model
/// @topic core
///
/// The domain model for the reference app. Demonstrates a simple value type
/// that conforms to `Equatable`, `Identifiable`, and `Sendable` — the three
/// protocols required for TCA state types.
///
/// Includes static preview and sample data for use in SwiftUI previews
/// and tests.

import Foundation
import IdentifiedCollections

// MARK: - Model

public struct Item: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var notes: String
    public var price: Decimal?
    public var title: String

    public init(
        id: UUID,
        notes: String = "",
        price: Decimal? = nil,
        title: String
    ) {
        self.id = id
        self.notes = notes
        self.price = price
        self.title = title
    }
}

// MARK: - Preview Data

extension Item {
    /// Single preview item — use positive UUIDs for previews
    public static let preview = Item(
        id: UUID(1),
        notes: "These are sample notes for the preview item.",
        price: 9.99,
        title: "Preview Item"
    )

    /// Multiple preview items for list previews
    public static let samples: IdentifiedArrayOf<Item> = [
        Item(
            id: UUID(1),
            notes: "First item notes.",
            price: 9.99,
            title: "Alpha Item"
        ),
        Item(
            id: UUID(2),
            notes: "Second item notes.",
            price: 19.99,
            title: "Beta Item"
        ),
        Item(
            id: UUID(3),
            notes: "",
            title: "Gamma Item"
        ),
    ]
}
