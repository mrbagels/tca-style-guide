/// # Items List Feature
/// @topic core
///
/// Demonstrates a list feature using ReduceChild to split action handling
/// into focused handler properties. Shows: loading on appear, pull-to-refresh,
/// swipe-to-delete, and delegate actions for router coordination.
///
/// ## Key Rules
/// - `IdentifiedArrayOf<Item>` for list state — never raw `[Item]`
/// - Delegate actions communicate navigation intent to the router
/// - `@Dependency` declared inside the reducer struct
/// - ReduceChild handlers alphabetized

import ComposableArchitecture
import Foundation
import IdentifiedCollections

// MARK: - Reducer

@Reducer
public struct ItemsListFeature {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Whether the list is loading
        var isLoading = false

        /// The list of items — uses `IdentifiedArrayOf` for O(1) lookup
        var items: IdentifiedArrayOf<Item> = []

        public init() {}
    }

    // MARK: - Action

    public enum Action: ViewAction {
        case delegate(Delegate)
        case `internal`(Internal)
        case view(View)

        @CasePathable
        public enum Delegate: Sendable {
            case addItemTapped
            case itemSelected(Item)
        }

        @CasePathable
        public enum Internal: Sendable {
            case deleteResponse(id: Item.ID, Result<Void, Error>)
            case fetchResponse(Result<IdentifiedArrayOf<Item>, Error>)
        }

        @CasePathable
        public enum View: Sendable {
            case addButtonTapped
            case deleteSwipeTapped(Item.ID)
            case itemRowTapped(Item)
            case onAppear
            case refreshTriggered
        }
    }

    // MARK: - Dependencies

    @Dependency(\.itemClient) var itemClient

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none
            default:
                return .none
            }
        }

        handleInternalActions
        handleViewActions
    }

    // MARK: - Internal Handler

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .deleteResponse(let id, .success):
                state.items.remove(id: id)
                return .none

            case .deleteResponse(_, .failure):
                /// Silently fail — item stays in list, user can retry
                return .none

            case .fetchResponse(.success(let items)):
                state.isLoading = false
                state.items = items
                return .none

            case .fetchResponse(.failure):
                state.isLoading = false
                return .none
            }
        }
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .addButtonTapped:
                return .send(.delegate(.addItemTapped))

            case .deleteSwipeTapped(let id):
                return .run { [itemClient] send in
                    await send(.internal(.deleteResponse(
                        id: id,
                        Result { try await itemClient.delete(id) }
                    )))
                }

            case .itemRowTapped(let item):
                return .send(.delegate(.itemSelected(item)))

            case .onAppear:
                state.isLoading = true
                return .run { [itemClient] send in
                    await send(.internal(.fetchResponse(
                        Result { try await itemClient.fetchAll() }
                    )))
                }

            case .refreshTriggered:
                return .run { [itemClient] send in
                    await send(.internal(.fetchResponse(
                        Result { try await itemClient.fetchAll() }
                    )))
                }
            }
        }
    }
}
