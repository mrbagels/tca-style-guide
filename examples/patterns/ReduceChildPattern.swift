/// # ReduceChild Pattern
/// @topic core
///
/// `ReduceChild` is a custom utility reducer that prevents "massive reducer syndrome"
/// by splitting action handling into focused, testable handler properties.
///
/// ## Variants
/// - `ReduceChild` — standard, extracts a specific action type from the parent action enum
/// - `ReduceChildWithState` — projects a state slice so the handler only sees relevant state
/// - `ReduceChild` with lifecycle hooks — adds `before`/`after` for cross-cutting concerns
///
/// ## Key Rules
/// - One `ReduceChild` per action category (view, internal, alert, etc.)
/// - Handlers are `private var` computed properties, alphabetized
/// - Never send parent/child/internal actions from a ReduceChild handler — only delegate

import ComposableArchitecture

// MARK: - ReduceChild Implementation

/// The core `ReduceChild` reducer. Extracts a child action from the parent
/// action enum and delegates handling to a focused closure.
public struct ReduceChild<State, Action, ChildAction>: Reducer {
    let casePath: CaseKeyPath<Action, ChildAction>
    let effectHandler: (inout State, ChildAction) -> Effect<Action>

    /// - Parameters:
    ///   - casePath: Key path to the child action case (e.g., `\.view`, `\.internal`)
    ///   - effectHandler: Closure that handles the child action and returns effects
    public init(
        _ casePath: CaseKeyPath<Action, ChildAction>,
        _ effectHandler: @escaping (inout State, ChildAction) -> Effect<Action>
    ) {
        self.casePath = casePath
        self.effectHandler = effectHandler
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        guard let childAction = AnyCasePath(casePath).extract(from: action) else {
            return .none
        }
        return effectHandler(&state, childAction)
    }
}

// MARK: - ReduceChildWithState Implementation

/// Projects a state slice so the handler only sees and modifies relevant state.
/// Ideal for multi-section forms or features where action categories map
/// to specific state slices.
public struct ReduceChildWithState<ParentState, ChildState, ParentAction, ChildAction>: Reducer {
    let statePath: WritableKeyPath<ParentState, ChildState>
    let casePath: CaseKeyPath<ParentAction, ChildAction>
    let effectHandler: (inout ChildState, ChildAction) -> Effect<ParentAction>

    /// - Parameters:
    ///   - statePath: Key path to the relevant state slice
    ///   - casePath: Key path to the child action case
    ///   - effectHandler: Closure operating on the projected state slice
    public init(
        state statePath: WritableKeyPath<ParentState, ChildState>,
        action casePath: CaseKeyPath<ParentAction, ChildAction>,
        toEffect effectHandler: @escaping (inout ChildState, ChildAction) -> Effect<ParentAction>
    ) {
        self.statePath = statePath
        self.casePath = casePath
        self.effectHandler = effectHandler
    }

    public func reduce(into state: inout ParentState, action: ParentAction) -> Effect<ParentAction> {
        guard let childAction = AnyCasePath(casePath).extract(from: action) else {
            return .none
        }
        return effectHandler(&state[keyPath: statePath], childAction)
    }
}

// MARK: - Lifecycle Hooks Extension

extension ReduceChild {
    /// Adds `before` and `after` hooks for cross-cutting concerns
    /// like analytics, logging, or timestamp tracking.
    ///
    /// ```swift
    /// ReduceChild(
    ///     \.view,
    ///     before: { state, action in
    ///         analytics.track("view_action", properties: ["action": "\(action)"])
    ///     },
    ///     after: { state, action, effect in
    ///         state.lastInteraction = Date()
    ///     },
    ///     toEffect: handleViewActions
    /// )
    /// ```
    public init(
        _ casePath: CaseKeyPath<Action, ChildAction>,
        before beforeHook: @escaping (inout State, ChildAction) -> Void,
        after afterHook: @escaping (inout State, ChildAction, Effect<Action>) -> Void,
        toEffect effectHandler: @escaping (inout State, ChildAction) -> Effect<Action>
    ) {
        self.casePath = casePath
        self.effectHandler = { state, action in
            beforeHook(&state, action)
            let effect = effectHandler(&state, action)
            afterHook(&state, action, effect)
            return effect
        }
    }
}

// MARK: - Usage Examples

/**
 ## Multi-Section Form with ReduceChildWithState

 ```swift
 @Reducer
 struct RegistrationFeature {
     @ObservableState
     struct State: Equatable {
         var personalInfo = PersonalInfoState()
         var accountSettings = AccountSettingsState()
     }

     enum Action {
         case accountSettings(AccountSettingsAction)
         case `internal`(Internal)
         case personalInfo(PersonalInfoAction)
     }

     var body: some ReducerOf<Self> {
         // Each handler only sees its state slice
         ReduceChildWithState(
             state: \.personalInfo,
             action: \.personalInfo,
             toEffect: handlePersonalInfo
         )

         ReduceChildWithState(
             state: \.accountSettings,
             action: \.accountSettings,
             toEffect: handleAccountSettings
         )

         // Validation needs full state → uses regular ReduceChild
         handleValidation
     }
 }
 ```
 */
private struct _UsageDocumentation {}
