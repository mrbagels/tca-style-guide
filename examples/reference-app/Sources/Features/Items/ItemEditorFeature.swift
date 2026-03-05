/// # Item Editor Feature
/// @topic architecture
///
/// A production-grade editing feature demonstrating: form validation, optimistic
/// save with rollback, cancellation with unsaved-changes alert, `CancelID` for
/// effect management, focus state, and delegate communication.
///
/// Follows the `CompleteFeaturePattern.swift` template. This is the most
/// complex leaf feature in the reference app.
///
/// ## Key Rules
/// - Validation lives in the reducer, never in the view
/// - Capture specific state values in `.run` closures — never the full `state`
/// - `CancelID` enum for typed cancellation
/// - Handle both `.success` and `.failure` of every `Result`
/// - Child features communicate via `.delegate` only

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct ItemEditorFeature {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Alert state — typed to the Alert action enum
        @Presents var alert: AlertState<Action.Alert>?

        /// Focus tracking for form fields — synced with SwiftUI via `.bind()`
        var focus: Field? = .title

        /// Whether a save operation is in flight
        var isSaving = false

        /// Form field: item notes (multi-line)
        var notes = ""

        /// Snapshot of the item before editing — used for unsaved changes detection
        var originalItem: Item?

        /// Form field: item price
        var price: Decimal?

        /// Form field: item title
        var title = ""

        /// Validation errors — computed per-field, displayed inline
        var validationErrors: [Field: String] = [:]

        public init() {}

        /// Convenience initializer for editing an existing item
        public init(item: Item) {
            self.notes = item.notes
            self.originalItem = item
            self.price = item.price
            self.title = item.title
        }
    }

    /// Focus field enum — mirrors form fields for `@FocusState` binding
    public enum Field: Hashable, Sendable {
        case notes
        case price
        case title
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case `internal`(Internal)
        case view(View)

        @CasePathable
        public enum Alert: Sendable {
            case discardChangesTapped
        }

        @CasePathable
        public enum Delegate: Sendable {
            case itemSaved(Item)
        }

        @CasePathable
        public enum Internal: Sendable {
            case saveResponse(Result<Item, Error>)
            case validationCompleted
        }

        @CasePathable
        public enum View: Sendable {
            case cancelButtonTapped
            case onAppear
            case saveButtonTapped
        }
    }

    // MARK: - Cancellation IDs

    private enum CancelID {
        case save
    }

    // MARK: - Dependencies

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.itemClient) var itemClient
    @Dependency(\.uuid) var uuid

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .send(.internal(.validationCompleted))

            case .delegate:
                return .none

            default:
                return .none
            }
        }

        handleAlertActions
        handleInternalActions
        handleViewActions

        .ifLet(\.$alert, action: \.alert)
    }

    // MARK: - Alert Handler

    private var handleAlertActions: ReduceChild<State, Action, PresentationAction<Action.Alert>> {
        ReduceChild(\.alert) { state, action in
            switch action {
            case .presented(.discardChangesTapped):
                return .run { [dismiss] _ in
                    await dismiss()
                }

            case .dismiss:
                return .none
            }
        }
    }

    // MARK: - Internal Handler

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .saveResponse(.success(let savedItem)):
                state.isSaving = false
                state.originalItem = savedItem
                return .send(.delegate(.itemSaved(savedItem)))

            case .saveResponse(.failure):
                state.isSaving = false
                state.alert = AlertState {
                    TextState("Save Failed")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Could not save your changes. Please try again.")
                }
                return .none

            case .validationCompleted:
                state.validationErrors = validate(state: state)
                return .none
            }
        }
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .cancelButtonTapped:
                let hasChanges = state.title != (state.originalItem?.title ?? "")
                    || state.notes != (state.originalItem?.notes ?? "")
                    || state.price != state.originalItem?.price

                if hasChanges {
                    state.alert = AlertState {
                        TextState("Discard Changes?")
                    } actions: {
                        ButtonState(role: .destructive, action: .discardChangesTapped) {
                            TextState("Discard")
                        }
                        ButtonState(role: .cancel) {
                            TextState("Keep Editing")
                        }
                    }
                    return .none
                } else {
                    return .run { [dismiss] _ in
                        await dismiss()
                    }
                }

            case .onAppear:
                return .send(.internal(.validationCompleted))

            case .saveButtonTapped:
                let errors = validate(state: state)
                state.validationErrors = errors
                guard errors.isEmpty else {
                    state.focus = errors.keys.sorted(by: { "\($0)" < "\($1)" }).first
                    return .none
                }

                state.isSaving = true

                /// Capture specific values — NEVER capture `state` itself (G4, G16)
                let id = state.originalItem?.id ?? uuid()
                let notes = state.notes
                let price = state.price
                let title = state.title

                return .run { [itemClient] send in
                    let item = Item(
                        id: id,
                        notes: notes,
                        price: price,
                        title: title
                    )
                    await send(.internal(.saveResponse(Result {
                        try await itemClient.save(item)
                    })))
                }
                .cancellable(id: CancelID.save)
            }
        }
    }

    // MARK: - Validation

    /// Validation lives in the reducer — never in the view.
    private func validate(state: State) -> [Field: String] {
        var errors: [Field: String] = [:]

        if state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.title] = "Title is required"
        } else if state.title.count > 100 {
            errors[.title] = "Title must be under 100 characters"
        }

        if let price = state.price, price < 0 {
            errors[.price] = "Price cannot be negative"
        }

        return errors
    }
}
