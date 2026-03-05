/// # Item Detail Feature
/// @topic core
///
/// Detail view feature with child presentation (editor sheet) and delegate
/// communication. Demonstrates `@Reducer enum Destination` for modal
/// presentation, `.ifLet(\.$destination)` composition, and handling child
/// delegate actions to update local state.
///
/// ## Key Rules
/// - `@Reducer enum Destination` for presented children
/// - `.ifLet(\.$destination, action: \.destination)` goes LAST in body
/// - Handle child `.delegate` in a `Reduce` passthrough
/// - Delegate upward to router for delete coordination

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct ItemDetailFeature {

    // MARK: - Destination

    @Reducer
    public enum Destination {
        case edit(ItemEditorFeature)
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Alert for delete confirmation
        @Presents var alert: AlertState<Action.Alert>?

        /// Modal destination — editor sheet
        @Presents var destination: Destination.State?

        /// The item being displayed
        var item: Item

        /// Whether a delete operation is in flight
        var isDeleting = false

        public init(item: Item) {
            self.item = item
        }
    }

    // MARK: - Action

    public enum Action: ViewAction {
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        case `internal`(Internal)
        case view(View)

        @CasePathable
        public enum Alert: Sendable {
            case confirmDeleteTapped
        }

        @CasePathable
        public enum Delegate: Sendable {
            case itemDeleted(Item.ID)
            case itemUpdated(Item)
        }

        @CasePathable
        public enum Internal: Sendable {
            case deleteResponse(Result<Void, Error>)
        }

        @CasePathable
        public enum View: Sendable {
            case deleteButtonTapped
            case editButtonTapped
        }
    }

    // MARK: - Cancellation IDs

    private enum CancelID {
        case delete
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

        handleAlertActions
        handleDestinationDelegation
        handleInternalActions
        handleViewActions

        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Alert Handler

    private var handleAlertActions: ReduceChild<State, Action, PresentationAction<Action.Alert>> {
        ReduceChild(\.alert) { state, action in
            switch action {
            case .presented(.confirmDeleteTapped):
                state.isDeleting = true
                let itemID = state.item.id
                return .run { [itemClient] send in
                    await send(.internal(.deleteResponse(Result {
                        try await itemClient.delete(itemID)
                    })))
                }
                .cancellable(id: CancelID.delete)

            case .dismiss:
                return .none
            }
        }
    }

    // MARK: - Destination Delegation

    /// Handles delegate actions from the editor child feature.
    private var handleDestinationDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.edit(.delegate(.itemSaved(let item))))):
                state.item = item
                state.destination = nil
                return .send(.delegate(.itemUpdated(item)))

            default:
                return .none
            }
        }
    }

    // MARK: - Internal Handler

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .deleteResponse(.success):
                state.isDeleting = false
                let itemID = state.item.id
                return .send(.delegate(.itemDeleted(itemID)))

            case .deleteResponse(.failure):
                state.isDeleting = false
                state.alert = AlertState {
                    TextState("Delete Failed")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Could not delete this item. Please try again.")
                }
                return .none
            }
        }
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("Delete Item?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeleteTapped) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("This action cannot be undone.")
                }
                return .none

            case .editButtonTapped:
                state.destination = .edit(
                    ItemEditorFeature.State(item: state.item)
                )
                return .none
            }
        }
    }
}
