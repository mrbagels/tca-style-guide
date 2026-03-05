/// # Items List View
/// @topic view
///
/// List view with rows, swipe-to-delete, pull-to-refresh, and an add button.
/// Demonstrates `.task` for initial load, `.refreshable` for pull-to-refresh,
/// and `@ViewAction` for all user interactions.
///
/// ## Key Rules
/// - Use `.task` instead of `.onAppear` for async lifecycle
/// - Use `.refreshable` with `send(.refreshTriggered)` for pull-to-refresh
/// - Swipe actions use `send(.deleteSwipeTapped(id))` — not inline mutation
/// - Extract row views as `private func` for reuse

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: ItemsListFeature.self)
public struct ItemsListView: View {
    public var store: StoreOf<ItemsListFeature>

    public init(store: StoreOf<ItemsListFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.isLoading && store.items.isEmpty {
                ProgressView("Loading...")
            } else if store.items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .navigationTitle("Items")
        .toolbar { toolbarContent }
        .task { send(.onAppear) }
    }

    // MARK: - Sections

    private var itemsList: some View {
        List {
            ForEach(store.items) { item in
                itemRow(item)
            }
        }
        .refreshable { send(.refreshTriggered) }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Items",
            systemImage: "tray",
            description: Text("Tap + to add your first item.")
        )
    }

    // MARK: - Row

    private func itemRow(_ item: Item) -> some View {
        Button {
            send(.itemRowTapped(item))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let price = item.price {
                    Text(price, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                send(.deleteSwipeTapped(item.id))
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                send(.addButtonTapped)
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}
