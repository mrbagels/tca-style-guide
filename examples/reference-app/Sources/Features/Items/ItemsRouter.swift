/// # Items Router
/// @topic navigation
///
/// Navigation coordinator for the Items tab. Manages a `NavigationStack` with
/// push destinations (detail) and modal destinations (add/edit). Demonstrates
/// `@Reducer enum Path` for push nav, `@Reducer enum Destination` for modals,
/// `Scope` for root feature, and child delegation via `Reduce`.
///
/// ## Key Rules
/// - `@Reducer enum` for Path and Destination — TCA auto-generates case reducers
/// - Root is scoped first in the body
/// - `.forEach(\.path)` and `.ifLet(\.$destination)` go LAST
/// - Child delegation uses `Reduce` when coordinating multiple feature types
/// - Delegate upward to AppRouter for cross-tab coordination

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct ItemsRouter {

    // MARK: - Path & Destination

    /// Push navigation destinations
    @Reducer
    public enum Path {
        case detail(ItemDetailFeature)
    }

    /// Modal presentation destinations
    @Reducer
    public enum Destination {
        case addItem(ItemEditorFeature)
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Modal destination — add item sheet
        @Presents var destination: Destination.State?
        /// Push navigation stack
        var path = StackState<Path.State>()
        /// The root list screen
        var root = ItemsListFeature.State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: ViewAction {
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        case `internal`(Internal)
        case path(StackActionOf<Path>)
        case root(ItemsListFeature.Action)
        case view(View)

        @CasePathable
        public enum Delegate: Sendable {
            case itemCreated
        }

        @CasePathable
        public enum Internal: Sendable {
            case refreshList
        }

        @CasePathable
        public enum View: Sendable {
            case placeholder
        }
    }

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        Scope(state: \.root, action: \.root) {
            ItemsListFeature()
        }

        Reduce { state, action in
            switch action {
            case .delegate:
                return .none
            default:
                return .none
            }
        }

        handleChildDelegation
        handleInternalActions

        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Child Delegation

    /// Coordinates delegate actions from root, path, and destination children.
    /// Uses `Reduce` (not `ReduceChild`) because it matches across multiple
    /// child feature types — this is the ONE justified case.
    private var handleChildDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // Root list delegates
            case .root(.delegate(.addItemTapped)):
                state.destination = .addItem(ItemEditorFeature.State())
                return .none

            case .root(.delegate(.itemSelected(let item))):
                state.path.append(.detail(ItemDetailFeature.State(item: item)))
                return .none

            // Path detail delegates
            case .path(.element(_, action: .detail(.delegate(.itemDeleted)))):
                state.path.removeAll()
                return .send(.internal(.refreshList))

            case .path(.element(_, action: .detail(.delegate(.itemUpdated)))):
                return .send(.internal(.refreshList))

            // Destination (add item) delegates
            case .destination(.presented(.addItem(.delegate(.itemSaved)))):
                state.destination = nil
                return .merge(
                    .send(.internal(.refreshList)),
                    .send(.delegate(.itemCreated))
                )

            default:
                return .none
            }
        }
    }

    // MARK: - Internal Handler

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .refreshList:
                /// Trigger a refresh on the root list by sending its view action
                return .send(.root(.view(.refreshTriggered)))
            }
        }
    }
}
