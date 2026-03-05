/// # Settings Feature
/// @topic core
///
/// A simple leaf feature demonstrating `BindableAction` for two-way form
/// bindings (Toggle, Picker, TextField) and `Delegate` actions for parent
/// coordination. Settings does not need its own router — it's a single screen.
///
/// ## Key Rules
/// - `BindableAction` enables `$store.property` syntax in the view
/// - `BindingReducer()` must be first in the body
/// - Delegate actions communicate preference changes to AppRouter
/// - `@Dependency` declared inside the reducer struct

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct SettingsFeature {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Display name for the user
        var displayName = "User"

        /// Whether notifications are enabled
        var notificationsEnabled = true

        /// Selected sort order for items
        var sortOrder: SortOrder = .title

        public init() {}
    }

    /// Sort order options for the items list
    public enum SortOrder: String, CaseIterable, Sendable {
        case price
        case title
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)

        @CasePathable
        public enum Delegate: Sendable {
            case sortOrderChanged(SortOrder)
        }

        @CasePathable
        public enum View: Sendable {
            case resetButtonTapped
        }
    }

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding(\.sortOrder):
                return .send(.delegate(.sortOrderChanged(state.sortOrder)))

            case .binding, .delegate:
                return .none

            default:
                return .none
            }
        }

        handleViewActions
    }

    // MARK: - Handlers

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .resetButtonTapped:
                state.displayName = "User"
                state.notificationsEnabled = true
                state.sortOrder = .title
                return .send(.delegate(.sortOrderChanged(.title)))
            }
        }
    }
}
