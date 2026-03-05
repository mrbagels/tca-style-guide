/// # Feature Pattern
/// @topic core
///
/// Every TCA feature follows a four-part structure: State, Action, Reducer, View.
/// This file demonstrates the canonical feature layout with all conventions applied.
///
/// ## Key Rules
/// - `@Reducer` on the struct, suffix with `Feature`
/// - `@ObservableState` on State, conforming to `Equatable`
/// - Action conforms to `ViewAction` (and `BindableAction` only when needed)
/// - **Never** conform top-level Action to `Equatable`
/// - Dependencies declared inside the reducer struct via `@Dependency`
/// - `public init() {}` for package-level accessibility
/// - Alphabetize everything: imports, actions, enum cases, handlers, properties

import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Reducer

@Reducer
public struct ProfileFeature {

    // MARK: - State

    /// State uses `@ObservableState` for automatic SwiftUI observation.
    /// All properties are alphabetized. Use `@Presents` for optional
    /// presentation state (alerts, sheets, destinations).
    @ObservableState
    public struct State: Equatable {
        /// Alert presentation state — always typed to the Alert action enum
        @Presents var alert: AlertState<Action.Alert>?

        /// User display name bound via `BindableAction`
        var displayName = ""

        /// Loading flag for async operations
        var isLoading = false

        /// Required for package-level features
        public init() {}
    }

    // MARK: - Action

    /// Actions are organized into nested enums by responsibility.
    /// Top-level cases are alphabetized: alert, binding, delegate, internal, view.
    ///
    /// **Why no `Equatable`?** TCA 1.4+ uses `@CasePathable` key path syntax
    /// for `TestStore.receive`, so `Equatable` on Action is unnecessary and
    /// creates boilerplate with `Result` types.
    public enum Action: ViewAction, BindableAction {
        /// Alert presentation actions — wraps the Alert enum
        case alert(PresentationAction<Alert>)
        /// Two-way binding support for `$store.property` syntax
        case binding(BindingAction<State>)
        /// Communication TO parent features — parent observes these
        case delegate(Delegate)
        /// Business logic, API responses, timers — internal to this feature
        case `internal`(Internal)
        /// Direct user interactions from the UI
        case view(View)

        /// Alert button actions — always `@CasePathable` and `Sendable`
        @CasePathable
        public enum Alert: Sendable {
            case confirmDeleteTapped
        }

        /// Delegate actions the parent should observe.
        /// **Rule:** Parents ONLY observe child `.delegate` — never send
        /// child `.view` or `.internal` actions directly.
        @CasePathable
        public enum Delegate: Sendable {
            case profileDeleted
        }

        /// Internal business logic actions — API responses, computed results.
        /// These are never sent by parent or child features.
        @CasePathable
        public enum Internal: Sendable {
            case profileResponse(Result<Profile, Error>)
        }

        /// View actions are named after the literal user interaction,
        /// not the resulting effect.
        ///
        /// ```swift
        /// // CORRECT — describes what the user did
        /// case saveButtonTapped
        ///
        /// // INCORRECT — describes the effect
        /// case save
        /// ```
        @CasePathable
        public enum View: Sendable {
            case deleteButtonTapped
            case onAppear
            case saveButtonTapped
        }
    }

    // MARK: - Dependencies

    /// Dependencies are declared inside the `@Reducer` struct,
    /// not at file scope or in State.
    @Dependency(\.profileClient) var profileClient

    /// Required for package-level features
    public init() {}

    // MARK: - Reducer Body

    /// Composition order is strict:
    /// 1. `BindingReducer()` — processes bindings before anything else
    /// 2. `Scope` — child features reduce their own state first
    /// 3. `Reduce` — minimal, cross-cutting concerns only (binding/delegate passthrough)
    /// 4. `ReduceChild` handlers — focused handlers per action category (alphabetized)
    /// 5. `.ifLet` / `.forEach` — presentation modifiers always last
    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding, .delegate:
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

    // MARK: - Handlers

    /// Alert handler — uses `ReduceChild` with `PresentationAction` type.
    /// Always handle both `.presented(...)` and `.dismiss` cases.
    private var handleAlertActions: ReduceChild<State, Action, PresentationAction<Action.Alert>> {
        ReduceChild(\.alert) { state, action in
            switch action {
            case .presented(.confirmDeleteTapped):
                return .send(.delegate(.profileDeleted))
            case .dismiss:
                return .none
            }
        }
    }

    /// Internal handler — processes API responses and business logic.
    /// Pattern: always handle both `.success` and `.failure` of Result types.
    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .profileResponse(.success(let profile)):
                state.displayName = profile.name
                state.isLoading = false
                return .none
            case .profileResponse(.failure):
                state.isLoading = false
                return .none
            }
        }
    }

    /// View handler — translates user interactions into state changes and effects.
    ///
    /// **Critical rules:**
    /// - Never mutate state inside `.run` effects (state is captured by copy)
    /// - Capture specific state values in closures, not the full `state`
    /// - Cancel long-running effects on disappear
    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("Delete Profile?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeleteTapped) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                }
                return .none

            case .onAppear:
                state.isLoading = true
                return .run { [profileClient] send in
                    let result = await profileClient.fetch()
                    await send(.internal(.profileResponse(result)))
                }

            case .saveButtonTapped:
                /// Capture specific values — NOT `state` itself
                return .run { [profileClient, name = state.displayName] send in
                    let result = await profileClient.update(name)
                    await send(.internal(.profileResponse(result)))
                }
            }
        }
    }
}
