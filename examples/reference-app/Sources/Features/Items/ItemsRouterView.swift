/// # Items Router View
/// @topic view
///
/// `NavigationStack(path:)` view for the Items tab. Demonstrates store scoping
/// for root, path destinations via `store.case`, and modal presentation via
/// `.sheet(item:)`.
///
/// ## Key Rules
/// - `NavigationStack(path:)` binds to the router's `path` state
/// - `destination:` closure switches on `store.case` for type-safe routing
/// - Root view scoped at point of use
/// - Modals use `.sheet(item:)` with scoped store

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: ItemsRouter.self)
public struct ItemsRouterView: View {
    @Bindable public var store: StoreOf<ItemsRouter>

    public init(store: StoreOf<ItemsRouter>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            /// Root view — scoped at point of use
            ItemsListView(store: store.scope(state: \.root, action: \.root))
        } destination: { store in
            /// Switch on `store.case` for exhaustive, type-safe destination routing
            switch store.case {
            case .detail(let detailStore):
                ItemDetailView(store: detailStore)
            }
        }
        /// Add item modal — scoped at point of use
        .sheet(
            item: $store.scope(
                state: \.destination?.addItem,
                action: \.destination.addItem
            )
        ) { editorStore in
            ItemEditorView(store: editorStore)
        }
    }
}
