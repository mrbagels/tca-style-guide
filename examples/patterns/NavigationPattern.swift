/// # Navigation & Router Pattern
/// @topic navigation
///
/// Routers are specialized reducers that manage navigation. They contain:
/// 1. **Root feature** — the primary screen content
/// 2. **Path (StackState)** — push navigation via `NavigationStack`
/// 3. **Destination (@Presents)** — modal presentation (sheets, full screen covers)
///
/// ## Key Rules
/// - Use `@Reducer enum` for Path and Destination (TCA auto-generates case reducers)
/// - Root is scoped first in the body
/// - `.forEach(\.path)` and `.ifLet(\.$destination)` go LAST
/// - Child delegation uses `Reduce` when coordinating multiple feature types
/// - Avoid action ping-pong — coordinate in the parent via direct state mutation

import ComposableArchitecture
import SwiftUI

// MARK: - Router Reducer

@Reducer
public struct ItemsRouter {

    // MARK: - Path & Destination

    /// `@Reducer enum` for push navigation destinations.
    /// TCA auto-generates the reducer composition for each case.
    @Reducer
    public enum Path {
        case detail(ItemDetailFeature)
        case edit(EditItemFeature)
    }

    /// `@Reducer enum` for modal presentations (sheets, fullScreenCovers).
    @Reducer
    public enum Destination {
        case addItem(AddItemFeature)
        case filter(FilterFeature)
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Modal destination — uses `@Presents` for lifecycle management
        @Presents var destination: Destination.State?
        /// Push navigation stack
        var path = StackState<Path.State>()
        /// The root/landing screen feature
        var root = ItemsListFeature.State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
        /// Destination actions — modal presentations
        case destination(PresentationAction<Destination.Action>)
        case `internal`(Internal)
        /// Path actions — push navigation stack
        case path(StackActionOf<Path>)
        /// Root feature actions — always scoped
        case root(ItemsListFeature.Action)
        case view(View)

        @CasePathable
        public enum Delegate: Sendable {
            case itemCreated
        }

        @CasePathable
        public enum Internal: Sendable {
            case navigateToDetail(Item.ID)
        }

        @CasePathable
        public enum View: Sendable {
            case backTapped
        }
    }

    public init() {}

    // MARK: - Body

    /// Router body composition order:
    /// 1. BindingReducer
    /// 2. Scope root feature
    /// 3. Reduce (cross-cutting passthrough)
    /// 4. Handlers
    /// 5. `.forEach(\.path)` and `.ifLet(\.$destination)` — ALWAYS LAST
    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.root, action: \.root) {
            ItemsListFeature()
        }

        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none
            default:
                return .none
            }
        }

        handleInternalActions
        handleViewActions
        handleChildDelegation

        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Handlers

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .backTapped:
                state.path.removeLast()
                return .none
            }
        }
    }

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .navigateToDetail(let id):
                state.path.append(.detail(ItemDetailFeature.State(itemID: id)))
                return .none
            }
        }
    }

    /// Child delegation uses `Reduce` (not `ReduceChild`) when coordinating
    /// across multiple feature types — root, path elements, and destinations.
    /// This is the ONE place where `Reduce` over `ReduceChild` is justified.
    private var handleChildDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // Root feature delegation
            case .root(.delegate(.itemSelected(let id))):
                state.path.append(.detail(ItemDetailFeature.State(itemID: id)))
                return .none

            case .root(.delegate(.addItemTapped)):
                state.destination = .addItem(AddItemFeature.State())
                return .none

            // Path feature delegation
            case .path(.element(_, action: .detail(.delegate(.editRequested(let item))))):
                state.path.append(.edit(EditItemFeature.State(item: item)))
                return .none

            // Destination delegation — dismiss modal after completion
            case .destination(.presented(.addItem(.delegate(.itemCreated)))):
                state.destination = nil
                return .send(.delegate(.itemCreated))

            default:
                return .none
            }
        }
    }
}

// MARK: - Router View

/// Router views use `NavigationStack(path:)` with store scoping.
/// The `destination:` closure switches on `store.case` for type-safe routing.
@ViewAction(for: ItemsRouter.self)
public struct ItemsRouterView: View {
    @Bindable public var store: StoreOf<ItemsRouter>

    public init(store: StoreOf<ItemsRouter>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            /// Root view is scoped at point of use
            ItemsListView(store: store.scope(state: \.root, action: \.root))
        } destination: { store in
            /// Switch on `store.case` for exhaustive, type-safe destination routing
            switch store.case {
            case .detail(let detailStore):
                ItemDetailView(store: detailStore)
            case .edit(let editStore):
                EditItemView(store: editStore)
            }
        }
        /// Sheets use `item:` binding with scoped store
        .sheet(item: $store.scope(state: \.destination?.addItem, action: \.destination.addItem)) { addStore in
            AddItemView(store: addStore)
        }
    }
}
