# Personal TCA / SwiftUI / SQLiteData Style Guide

> A comprehensive, opinionated style guide for building production iOS applications with **The Composable Architecture (TCA)**, **SwiftUI**, and **SQLiteData**. Derived from production codebases and Point-Free best practices. All code examples are anonymized.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [TCA Feature Pattern](#2-tca-feature-pattern)
3. [Action Organization](#3-action-organization)
4. [Reducer Organization](#4-reducer-organization)
5. [The ReduceChild Pattern](#5-the-reducechild-pattern)
6. [View Organization](#6-view-organization)
7. [Navigation & Routing](#7-navigation--routing)
8. [State Management](#8-state-management)
9. [Dependency Management](#9-dependency-management)
10. [SQLiteData & Persistence](#10-sqlitedata--persistence)
11. [Naming Conventions](#11-naming-conventions)
12. [Code Style](#12-code-style)
13. [Testing](#13-testing)
14. [Common Gotchas & Pitfalls](#14-common-gotchas--pitfalls)
15. [Extensions Starter Kit](#15-extensions-starter-kit)

---

## 1. Introduction

### Purpose

This guide codifies the patterns, conventions, and best practices for building TCA/SwiftUI applications. It serves as a single reference for:

- Starting new projects with consistent architecture
- Onboarding new team members quickly
- Making architectural decisions with confidence
- Identifying and closing gaps against Point-Free (PFW) recommendations

### Philosophy

1. **Consistency over cleverness.** Every feature should look the same structurally, even if the logic differs.
2. **Alphabetical order everything.** Imports, actions, enum cases, handlers, properties. Reduces merge conflicts and makes things findable.
3. **Composition over monoliths.** Split reducers into focused handlers. Extract views into private computed properties. Keep things small.
4. **Exhaustive switching.** Prefer exhaustive `switch` statements. The compiler is your best reviewer.
5. **Test by default.** Architecture should make testing easy. Dependencies should be injectable. State should be inspectable.

### PFW Best-Practice Alignment

This guide incorporates Point-Free's recommended best practices directly into all templates and examples. Where our conventions intentionally differ from PFW defaults (e.g., the `Feature` suffix), the rationale is explained inline.

---

## 2. TCA Feature Pattern

Every feature follows the same four-part structure: **State**, **Action**, **Reducer**, **View**.

### Complete Feature Template

```swift
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
public struct ProfileFeature {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// User display name
        var displayName = ""

        /// Whether the profile is currently loading
        var isLoading = false

        /// Alert presentation state
        @Presents var alert: AlertState<Action.Alert>?

        public init() {}
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
            case confirmDeleteTapped
        }

        @CasePathable
        public enum Delegate: Sendable {
            case profileDeleted
        }

        @CasePathable
        public enum Internal: Sendable {
            case profileResponse(Result<Profile, Error>)
        }

        @CasePathable
        public enum View: Sendable {
            case deleteButtonTapped
            case onAppear
            case saveButtonTapped
        }
    }

    // MARK: - Dependencies

    @Dependency(\.profileClient) var profileClient

    public init() {}

    // MARK: - Reducer

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
                return .send(.internal(.profileResponse(
                    // Kick off fetch
                )))
            case .saveButtonTapped:
                return .run { [profileClient, name = state.displayName] send in
                    let result = await profileClient.update(name)
                    await send(.internal(.profileResponse(result)))
                }
            }
        }
    }
}
```

### Key Conventions

| Element | Convention |
|---|---|
| Struct annotation | `@Reducer` on the feature struct |
| Struct suffix | `Feature` (e.g., `ProfileFeature`, `SettingsFeature`) |
| State annotation | `@ObservableState` |
| State conformance | `Equatable` |
| Action protocols | `ViewAction`, `BindableAction` (when needed) — **never `Equatable`** |
| Dependencies | `@Dependency` properties declared inside the `@Reducer` struct |
| Initializer | `public init() {}` for package-level features |

**On the `Feature` suffix:** Point-Free's convention drops the suffix (e.g., `Profile` not `ProfileFeature`). Our convention uses it for clarity and to avoid naming conflicts with model types. Pick one and be consistent.

> **Gotchas to watch for in features:**
> - Never mutate state inside `.run` effects — state is value-type and captured by copy. See [G4](#g4-state-mutation-inside-effects).
> - Always capture specific state values in effect closures, not the full `state`. See [G16](#g16-capture-state-values-in-effect-closures).
> - Cancel long-running effects (timers, streams) on disappear. See [G5](#g5-long-running-effects-without-cancellation).

### Why No Equatable on Action?

**Do not** conform the top-level `Action` enum to `Equatable`. TCA does not require it, and it creates unnecessary boilerplate — especially when actions contain `Result` types, closures, or other non-Equatable payloads.

This is safe for testing because TCA 1.4+ introduced **case key path syntax** for `TestStore.receive`:

```swift
// Modern syntax — uses @CasePathable (auto-provided by @Reducer), not Equatable
await store.receive(\.internal.profileResponse.success) {
    $0.displayName = "Sample Name"
}

// Old syntax (required Equatable on Action) — avoid this
await store.receive(.internal(.profileResponse(.success(profile)))) { ... }
```

The `@Reducer` macro automatically generates `@CasePathable` conformance for your `Action` enum, which is all the key path syntax needs. You get full test coverage without `Equatable`.

---

## 3. Action Organization

### Nested Enum Pattern

Actions are organized into nested enums by responsibility:

```swift
public enum Action: ViewAction, BindableAction {
    // Alphabetical order for top-level cases
    case alert(PresentationAction<Alert>)     // A - Alert presentation
    case binding(BindingAction<State>)        // B - Binding actions
    case childFeature(ChildFeature.Action)    // C - Child feature actions
    case delegate(Delegate)                    // D - Parent communication
    case destination(PresentationAction<Destination.Action>) // D - Destination
    case `internal`(Internal)                 // I - Business logic
    case path(StackActionOf<Path>)            // P - Navigation path
    case view(View)                            // V - UI-triggered

    @CasePathable
    public enum Alert: Sendable {
        case confirmTapped
        case cancelTapped
    }

    @CasePathable
    public enum Delegate: Sendable {
        case didComplete
        case didRequestNavigation(Destination)
    }

    @CasePathable
    public enum Internal: Sendable {
        case dataLoaded(Result<[Item], Error>)
        case timerTicked
    }

    @CasePathable
    public enum View: Sendable {
        case addButtonTapped
        case itemSelected(Item.ID)
        case onAppear
        case refreshPulled
    }
}
```

### Action Responsibilities

| Category | Purpose | Examples |
|---|---|---|
| `view(View)` | Direct user interactions from the UI | `onAppear`, `saveButtonTapped`, `textChanged(String)` |
| `internal(Internal)` | Business logic, API responses, timers | `dataLoaded(Result<...>)`, `timerFired` |
| `delegate(Delegate)` | Communication to parent features | `didComplete`, `didSelectItem(Item)` |
| `alert(...)` | Alert/dialog presentation | `PresentationAction<Alert>` |
| `binding(...)` | Two-way binding support | `BindingAction<State>` |
| Child actions | Scoped child feature actions | `childFeature(ChildFeature.Action)` |

> **Gotcha:** Parents must only observe child `delegate` actions — never send child `.view` or `.internal` actions directly. See [G1](#g1-never-send-child-actions-directly-from-a-parent).

### Naming Rules

- **Name actions after literal user interactions**, not their effects:

```swift
// CORRECT - describes what the user did
case saveButtonTapped
case deleteSwipePerformed
case filterToggled(Filter)
case emailFieldChanged(String)

// INCORRECT - describes the effect
case save
case deleteItem
case toggleFilter(Filter)
case updateEmail(String)
```

- **Alphabetize** all cases within each enum
- **Mark nested enums** with `@CasePathable` and `Sendable`
- **Never add `Equatable`** to the top-level `Action` enum (see [Why No Equatable on Action?](#why-no-equatable-on-action))

---

## 4. Reducer Organization

### Body Structure Template

The reducer body follows a strict composition order:

```swift
public var body: some ReducerOf<Self> {
    // 1. BindingReducer (if using BindableAction)
    BindingReducer()

    // 2. Child feature scopes (if any)
    Scope(state: \.childFeature, action: \.childFeature) {
        ChildFeature()
    }

    // 3. Minimal main Reduce for cross-cutting concerns only
    Reduce { state, action in
        switch action {
        case .binding, .delegate:
            return .none
        default:
            return .none
        }
    }

    // 4. Composed ReduceChild handlers (alphabetical)
    handleAlertActions
    handleChildDelegation       // if needed
    handleInternalActions
    handleViewActions

    // 5. Presentation modifiers (last)
    .ifLet(\.$alert, action: \.alert)
    .ifLet(\.$destination, action: \.destination) {
        Destination.body
    }
}
```

### Composition Order Rationale

1. **BindingReducer first** - Processes binding actions before anything else. Omitting it when `Action: BindableAction` causes silent binding failures. See [G2](#g2-missing-bindingreducer).
2. **Scopes second** - Child features reduce their own state before parent reacts
3. **Main Reduce third** - Cross-cutting concerns (binding passthrough, delegate passthrough)
4. **ReduceChild handlers fourth** - Focused handlers for each action category
5. **Presentations last** - `.ifLet` / `.forEach` modifiers handle optional/collection state lifecycle. Forgetting these means child reducers never run. See [G3](#g3-missing-iflet--foreach-reducer-composition).

### When to Use ReduceChild vs Reduce

| Scenario | Use |
|---|---|
| Handling a single action category | `ReduceChild` (always) |
| Cross-cutting concerns (binding/delegate passthrough) | `Reduce` in main body |
| Complex child delegation coordinating multiple feature types in routers | `Reduce` (with comment explaining why) |
| Anything else | `ReduceChild` |

---

## 5. The ReduceChild Pattern

`ReduceChild` is a custom utility reducer that prevents "massive reducer syndrome" by splitting action handling into focused, testable handler properties.

### 5.1 ReduceChild (Standard)

Extracts and handles a specific action type from the parent action enum.

**Signature:**
```swift
public struct ReduceChild<State, Action, ChildAction>: Reducer {
    public init(
        _ casePath: CaseKeyPath<Action, ChildAction>,
        _ effectHandler: @escaping (inout State, ChildAction) -> Effect<Action>
    )
}
```

**Usage as a private computed property:**
```swift
private var handleViewActions: ReduceChild<State, Action, Action.View> {
    ReduceChild(\.view) { state, action in
        switch action {
        case .onAppear:
            state.isLoading = true
            return .send(.internal(.fetchData))
        case .saveButtonTapped:
            return .run { [client, name = state.name] send in
                let result = await client.save(name)
                await send(.internal(.saveResponse(result)))
            }
        }
    }
}

private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
    ReduceChild(\.internal) { state, action in
        switch action {
        case .fetchData:
            return .run { [client] send in
                let result = await client.fetch()
                await send(.internal(.dataResponse(result)))
            }
        case .dataResponse(.success(let data)):
            state.items = data
            state.isLoading = false
            return .none
        case .dataResponse(.failure):
            state.isLoading = false
            return .none
        case .saveResponse(.success):
            return .send(.delegate(.didSave))
        case .saveResponse(.failure):
            state.alert = .saveFailedAlert
            return .none
        }
    }
}
```

**For presentation actions (alerts, destinations):**
```swift
private var handleAlertActions: ReduceChild<State, Action, PresentationAction<Action.Alert>> {
    ReduceChild(\.alert) { state, action in
        switch action {
        case .presented(.confirmTapped):
            state.alert = nil
            return .send(.internal(.performDelete))
        case .presented(.cancelTapped):
            return .none
        case .dismiss:
            state.alert = nil
            return .none
        }
    }
}
```

**For child feature delegation:**
```swift
private var handleChildDelegation: ReduceChild<State, Action, PresentationAction<EditFeature.Action>> {
    ReduceChild(\.editFeature) { state, action in
        switch action {
        case .presented(.delegate(.didSave)):
            state.editFeature = nil
            return .send(.internal(.refreshData))
        case .dismiss:
            return .none
        default:
            return .none
        }
    }
}
```

> **Gotcha:** Only observe child `.delegate` actions. Never send child `.view` or `.internal` actions from a parent — this breaks encapsulation and makes refactoring impossible. See [G1](#g1-never-send-child-actions-directly-from-a-parent).

### 5.2 ReduceChildWithState (Advanced)

Projects a state slice so the handler only sees and modifies relevant state. Ideal for multi-section forms or features where action categories map to specific state slices.

**Signature:**
```swift
public struct ReduceChildWithState<ParentState, ChildState, ParentAction, ChildAction>: Reducer {
    public init(
        state statePath: WritableKeyPath<ParentState, ChildState>,
        action casePath: CaseKeyPath<ParentAction, ChildAction>,
        toEffect effectHandler: @escaping (inout ChildState, ChildAction) -> Effect<ParentAction>
    )
}
```

**Usage - Multi-section form:**
```swift
@Reducer
struct RegistrationFeature {
    @ObservableState
    struct State: Equatable {
        var personalInfo = PersonalInfoState()
        var accountSettings = AccountSettingsState()
    }

    enum Action {
        case personalInfo(PersonalInfoAction)
        case accountSettings(AccountSettingsAction)
        case `internal`(Internal)
        // ...
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

        // Validation needs full state, so uses regular ReduceChild
        handleValidation
    }

    private func handlePersonalInfo(
        into state: inout PersonalInfoState,
        action: PersonalInfoAction
    ) -> Effect<Action> {
        switch action {
        case .nameChanged(let name):
            state.name = name
            return .send(.internal(.validateField(.name)))
        case .emailChanged(let email):
            state.email = email
            return .send(.internal(.validateField(.email)))
        }
    }

    private func handleAccountSettings(
        into state: inout AccountSettingsState,
        action: AccountSettingsAction
    ) -> Effect<Action> {
        switch action {
        case .usernameChanged(let username):
            state.username = username
            return .none
        case .passwordChanged(let password):
            state.password = password
            return .none
        }
    }
}
```

### 5.3 ReduceChild with Lifecycle Hooks

Adds `before` and `after` hooks for cross-cutting concerns like analytics, logging, or timestamp tracking.

**Signature:**
```swift
extension ReduceChild {
    public init(
        _ casePath: CaseKeyPath<Action, ChildAction>,
        before beforeHook: @escaping (inout State, ChildAction) -> Void,
        after afterHook: @escaping (inout State, ChildAction, Effect<Action>) -> Void,
        toEffect effectHandler: @escaping (inout State, ChildAction) -> Effect<Action>
    )
}
```

**Usage - Analytics and debugging:**
```swift
ReduceChild(
    \.view,
    before: { state, action in
        // Track analytics for all view actions
        analytics.track("view_action", properties: ["action": "\(action)"])
    },
    after: { state, action, effect in
        state.lastInteraction = Date()
        #if DEBUG
        print("Processed: \(action)")
        #endif
    },
    toEffect: handleViewActions
)
```

### Handler Naming Conventions

| Handler | Naming Pattern |
|---|---|
| View actions | `handleViewActions` |
| Internal actions | `handleInternalActions` |
| Alert actions | `handleAlertActions` |
| Delegate actions | `handleDelegateActions` (rare - usually passthrough) |
| Child delegation | `handleChildDelegation` or `handle[ChildName]Delegation` |
| Presentation child | `handle[ChildName]Actions` |

---

## 6. View Organization

### @ViewAction Macro Usage

Every TCA view uses the `@ViewAction` macro for clean action sending:

```swift
@ViewAction(for: ProfileFeature.self)
public struct ProfileView: View {
    @Bindable public var store: StoreOf<ProfileFeature>

    public init(store: StoreOf<ProfileFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            headerSection
            contentSection
            actionButtons
        }
        .task { send(.onAppear) }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}
```

### Body Structure: Delegate to Private Vars

Keep the body minimal by delegating to private computed properties:

```swift
public var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            headerSection
            contentList
            footerActions
        }
        .navigationTitle("Profile")
        .toolbar { toolbarContent }
        .sheet(item: $store.scope(state: \.editSheet, action: \.editSheet)) { editStore in
            EditView(store: editStore)
        }
    }
}

// MARK: - Sections

private var headerSection: some View {
    VStack(spacing: 12) {
        Text(store.displayName)
            .font(.title)
        Text(store.email)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .padding()
}

@ViewBuilder
private var contentList: some View {
    if store.isLoading {
        ProgressView()
    } else {
        List(store.items) { item in
            ItemRow(item: item)
        }
    }
}

private var footerActions: some View {
    Button("Save") {
        send(.saveButtonTapped)
    }
    .buttonStyle(.borderedProminent)
    .padding()
}

@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { send(.doneButtonTapped) }
    }
}
```

### Subview Extraction Rules

| Guideline | Rule |
|---|---|
| **When to extract** | Any section > 10 lines, or logically distinct |
| **Naming** | Descriptive of content: `headerSection`, `actionButtons`, `emptyStateView` |
| **Annotation** | Use `@ViewBuilder` if the property has conditional logic |
| **Access** | Always `private` |
| **Store scoping** | Scope at the point of use, not in the parent |

### Store Scoping at Point of Use

```swift
// CORRECT - scope where it's used
.sheet(item: $store.scope(state: \.editProfile, action: \.editProfile)) { editStore in
    EditProfileView(store: editStore)
}

// For inline child features
ChildFeatureView(
    store: store.scope(state: \.childFeature, action: \.childFeature)
)
```

### Focus State Management

```swift
@ViewAction(for: LoginFeature.self)
struct LoginView: View {
    @Bindable var store: StoreOf<LoginFeature>
    @FocusState var focus: LoginFeature.Field?

    var body: some View {
        Form {
            TextField("Email", text: $store.email)
                .focused($focus, equals: .email)
            SecureField("Password", text: $store.password)
                .focused($focus, equals: .password)
        }
        .bind($store.focus, to: $focus)
    }
}
```

**Important:** Never use `Binding.init(get:set:)` to create bindings to store state. Always use `$store.propertyName` with `@Bindable` instead. The `Binding(get:set:)` pattern bypasses TCA's state management and can cause subtle bugs. See [G10](#g10-bindinginitgetset-bypasses-tca).

> **Gotcha:** Avoid sending actions on every frame for scroll offsets, drag gestures, or slider changes. This is expensive because every action traverses the entire reducer hierarchy. Debounce high-frequency inputs or keep them in local `@State`. See [G8](#g8-high-frequency-actions).

---

## 7. Navigation & Routing

### Router Pattern Overview

Routers are specialized reducers that manage navigation. They contain:

1. **Root feature** - The primary screen content
2. **Path (StackState)** - Push navigation via `NavigationStack`
3. **Destination (@Presents)** - Modal presentation (sheets, full screen covers)

### Router Template

```swift
@Reducer
public struct ItemsRouter {

    @Reducer
    public enum Path {
        case detail(ItemDetailFeature)
        case edit(EditItemFeature)
    }

    @Reducer
    public enum Destination {
        case addItem(AddItemFeature)
        case filter(FilterFeature)
    }

    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        var path = StackState<Path.State>()
        var root = ItemsListFeature.State()

        public init() {}
    }

    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
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
            case navigateToDetail(Item.ID)
        }

        @CasePathable
        public enum View: Sendable {
            case backTapped
        }
    }

    public init() {}

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

    /// Child delegation uses Reduce when coordinating multiple feature types
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

            // Destination delegation
            case .destination(.presented(.addItem(.delegate(.itemCreated)))):
                state.destination = nil
                return .send(.delegate(.itemCreated))

            default:
                return .none
            }
        }
    }
}
```

> **Gotchas for routers:**
> - Avoid action ping-pong between features — coordinate in the parent reducer via direct state mutation instead of bouncing actions. See [G6](#g6-action-ping-pong).
> - When using `cancelInFlight: true` inside a reducer composed with `.forEach`, use a per-instance cancellation ID (e.g., `state.id`) — a static ID cancels across all instances. See [G9](#g9-cancelinflight-with-reused-reducers).

### Router View (ContentView Pattern)

```swift
@ViewAction(for: ItemsRouter.self)
public struct ItemsRouterView: View {
    @Bindable public var store: StoreOf<ItemsRouter>

    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ItemsListView(store: store.scope(state: \.root, action: \.root))
        } destination: { store in
            switch store.case {
            case .detail(let detailStore):
                ItemDetailView(store: detailStore)
            case .edit(let editStore):
                EditItemView(store: editStore)
            }
        }
        .sheet(item: $store.scope(state: \.destination?.addItem, action: \.destination.addItem)) { addStore in
            NavigationStack {
                AddItemView(store: addStore)
            }
        }
        .fullScreenCover(
            item: $store.scope(state: \.destination?.filter, action: \.destination.filter)
        ) { filterStore in
            FilterView(store: filterStore)
        }
    }
}
```

### Navigation Types

| Type | Implementation | Use Case |
|---|---|---|
| **Push** | `StackState<Path.State>` / `NavigationStack` | Detail screens, drill-downs |
| **Sheet** | `@Presents var destination` / `.sheet(item:)` | Forms, pickers, secondary flows |
| **Full Screen Cover** | `@Presents var destination` / `.fullScreenCover(item:)` | Major modal flows, documents |

> **Gotcha:** Avoid constructing child state inside `NavigationLink(state:)` — dependencies may not be wired in the view layer. Construct navigation state in the reducer instead. See [G12](#g12-navigationlinkstate-with-dependencies).

---

## 8. State Management

### @ObservableState

All feature states use `@ObservableState`:

```swift
@ObservableState
public struct State: Equatable {
    var items: IdentifiedArrayOf<Item> = []
    var isLoading = false
    var searchText = ""

    public init() {}
}
```

`@ObservableState` replaces the older `@BindableState` pattern. Individual properties no longer need `@BindableState` annotation — the macro handles observation automatically.

> **Gotcha:** Do not add `willSet` / `didSet` property observers to `@ObservableState` properties — they interact with observation tracking and can cause infinite re-render loops. Derive state in the reducer instead. See [G11](#g11-willset--didset-in-state-causes-infinite-loops).

### @Shared for Cross-Feature State

Use `@Shared` with persistence strategies for state that multiple features need:

```swift
@ObservableState
public struct State: Equatable {
    /// Shared across features, persisted to app storage
    @Shared(.appStorage("selectedTheme")) var theme: Theme = .system

    /// Shared across features, persisted to file system
    @Shared(.fileStorage(.userProfileURL)) var userProfile: UserProfile?

    /// Shared across features, in memory only (reset on app launch)
    @Shared(.inMemory("currentSession")) var session: Session?
}
```

**Mutating shared state:**
```swift
// Use withLock for mutations
state.$session.withLock { $0 = newSession }

// Direct assignment also works for simple cases
state.theme = .dark
```

> **Gotcha:** `@Shared` has reference semantics — it can be mutated from effects without sending actions, bypassing TCA's unidirectional data flow. Use it sparingly and always mutate via `$shared.withLock { }`. See [G7](#g7-shared-reference-semantics-surprise).

**Custom persistence keys:**
```swift
extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasCompletedOnboarding: Self {
        Self[.appStorage("hasCompletedOnboarding"), default: false]
    }
}

// Usage
@Shared(.hasCompletedOnboarding) var hasCompletedOnboarding
```

### @Presents for Optional Child Features

```swift
@ObservableState
public struct State: Equatable {
    /// nil = dismissed, non-nil = presented
    @Presents var editProfile: EditProfileFeature.State?
    @Presents var alert: AlertState<Action.Alert>?
}
```

---

## 9. Dependency Management

### @DependencyClient Definition

```swift
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ItemClient: Sendable {
    /// Fetch all items
    public var fetchAll: @Sendable () async throws -> [Item]

    /// Fetch a single item by ID
    public var fetch: @Sendable (Item.ID) async throws -> Item

    /// Create a new item
    public var create: @Sendable (Item.Draft) async throws -> Item

    /// Update an existing item
    public var update: @Sendable (Item) async throws -> Item

    /// Delete an item
    public var delete: @Sendable (Item.ID) async throws -> Void
}
```

### Dependency Registration

```swift
// Register with DependencyValues
extension DependencyValues {
    public var itemClient: ItemClient {
        get { self[ItemClient.self] }
        set { self[ItemClient.self] = newValue }
    }
}
```

### Live Implementation (Separate File)

**File: `ItemClient+Live.swift`**

```swift
import Dependencies
import Foundation
import Networking

extension ItemClient: DependencyKey {
    public static let liveValue: ItemClient = {
        @Dependency(\.networkClient) var networkClient
        @Dependency(\.jsonDecoding) var jsonDecoding

        return ItemClient(
            fetchAll: {
                let (data, _) = try await networkClient.request(ItemEndpoints.list)
                return try jsonDecoding.decode([Item].self, from: data)
            },
            fetch: { id in
                let (data, _) = try await networkClient.request(ItemEndpoints.get(id))
                return try jsonDecoding.decode(Item.self, from: data)
            },
            create: { draft in
                let (data, _) = try await networkClient.request(ItemEndpoints.create(draft))
                return try jsonDecoding.decode(Item.self, from: data)
            },
            update: { item in
                let (data, _) = try await networkClient.request(ItemEndpoints.update(item))
                return try jsonDecoding.decode(Item.self, from: data)
            },
            delete: { id in
                _ = try await networkClient.request(ItemEndpoints.delete(id))
            }
        )
    }()
}
```

### Test/Preview Implementations

```swift
extension ItemClient: TestDependencyKey {
    public static let testValue = ItemClient()  // @DependencyClient generates unimplemented stubs

    public static let previewValue = ItemClient(
        fetchAll: { Item.samples },
        fetch: { _ in Item.sample },
        create: { draft in Item(id: UUID(), name: draft.name) },
        update: { $0 },
        delete: { _ in }
    )
}
```

### Actor-Based Implementation (Complex Clients)

For clients that need internal mutable state or coordination:

```swift
extension AuthClient: DependencyKey {
    public static let liveValue: AuthClient = {
        let coordinator = AuthCoordinator()

        return AuthClient(
            login: { username, password in
                await coordinator.login(username: username, password: password)
            },
            logout: { reason in
                await coordinator.logout(reason: reason)
            },
            events: {
                coordinator.events
            }
        )
    }()
}

/// Actor manages internal state thread-safely
private actor AuthCoordinator {
    private let eventContinuation: AsyncStream<AuthEvent>.Continuation
    let events: AsyncStream<AuthEvent>

    @Dependency(\.networkClient) private var networkClient
    @Dependency(\.keychain) private var keychain

    init() {
        (events, eventContinuation) = AsyncStream<AuthEvent>.makeStream()
    }

    func login(username: String, password: String) async -> Result<Session, AuthError> {
        // ... implementation
    }

    func logout(reason: LogoutReason) async {
        // ... cleanup
        eventContinuation.yield(.loggedOut(reason: reason))
    }
}
```

### File Organization

```
Clients/
  ItemClient/
    ItemClient.swift           # @DependencyClient definition + DependencyValues extension
    ItemClient+Live.swift      # DependencyKey conformance + live implementation
    Endpoints/
      ItemEndpoints.swift      # API endpoint definitions
```

Declare `@Dependency` properties **inside** the `@Reducer` struct, not at the top of the file. This keeps dependencies scoped to where they're used and makes testing clearer.

---

## 10. SQLiteData & Persistence

SQLiteData is Point-Free's fast, lightweight replacement for SwiftData, powered by SQLite and GRDB.

### 10.1 Model Definition

Use the `@Table` macro to define database-backed models:

```swift
import SQLiteData

@Table
struct Item: Hashable, Identifiable {
    let id: UUID
    var title = ""
    var notes = ""
    var isCompleted = false
    var position = 0
    var priority: Priority?
    var listID: ItemList.ID

    enum Priority: Int, QueryBindable {
        case low = 1
        case medium
        case high
    }
}

@Table
struct ItemList: Hashable, Identifiable {
    let id: UUID
    var title = ""
    var position = 0
}
```

**Column transformations** for custom types:

```swift
@Table
struct ItemList: Hashable, Identifiable {
    let id: UUID
    @Column(as: Color.HexRepresentation.self)
    var color: Color = .blue
    var title = ""
}
```

**Custom primary keys:**

```swift
@Table
struct ListAsset: Hashable, Identifiable {
    @Column(primaryKey: true)
    let listID: ItemList.ID
    var coverImage: Data?
    var id: ItemList.ID { listID }
}
```

**Junction tables (many-to-many):**

```swift
@Table("itemsTags")
struct ItemTag: Identifiable {
    let id: UUID
    let itemID: Item.ID
    let tagID: Tag.ID
}
```

### 10.2 @Selection for Custom Projections

Use `@Selection` when you need a custom shape from a query (not a full table row):

```swift
@Selection
struct ItemListRow: Identifiable {
    var id: ItemList.ID { list.id }
    var itemCount: Int
    var list: ItemList
}

@Selection
struct Stats {
    var totalCount = 0
    var completedCount = 0
    var overdueCount = 0
}
```

### 10.3 Database Setup

```swift
import OSLog
import SQLiteData
import SwiftUI

@main
struct MyApp: App {
    init() {
        prepareDependencies {
            $0.defaultDatabase = try! appDatabase()
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    var configuration = Configuration()

    #if DEBUG
    configuration.prepareDatabase { db in
        db.trace(options: .profile) {
            if context == .preview {
                print("\($0.expandedDescription)")
            } else {
                logger.debug("\($0.expandedDescription)")
            }
        }
    }
    #endif

    let database = try defaultDatabase(configuration: configuration)

    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("Create initial tables") { db in
        try #sql("""
            CREATE TABLE "itemLists" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "items" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "isCompleted" INTEGER NOT NULL DEFAULT 0,
                "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "priority" INTEGER,
                "listID" TEXT NOT NULL REFERENCES "itemLists"("id") ON DELETE CASCADE
            ) STRICT
            """).execute(db)
    }

    try migrator.migrate(database)
    return database
}

private let logger = Logger(subsystem: "MyApp", category: "Database")
```

### 10.4 Bootstrap Pattern (with iCloud Sync)

```swift
extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        defaultDatabase = try appDatabase()
        defaultSyncEngine = try SyncEngine(
            for: defaultDatabase,
            tables: ItemList.self, Item.self, Tag.self, ItemTag.self
        )
    }
}

// Usage in app entry point
@main
struct MyApp: App {
    init() {
        try! prepareDependencies {
            try $0.bootstrapDatabase()
        }
    }
}
```

### 10.5 Observation with @FetchAll, @FetchOne, @Fetch

**@FetchAll** - Observe all matching records:

```swift
// Simple - all records
@FetchAll var items: [Item]

// Filtered and sorted
@FetchAll(
    Item.where { !$0.isCompleted }.order { $0.position.asc() },
    animation: .default
)
var activeItems

// With joins and custom projection
@FetchAll(
    ItemList
        .group(by: \.id)
        .order(by: \.position)
        .leftJoin(Item.all) { $0.id.eq($1.listID) && !$1.isCompleted }
        .select {
            ItemListRow.Columns(
                itemCount: $1.id.count(),
                list: $0
            )
        },
    animation: .default
)
var listRows
```

**@FetchOne** - Observe a single value:

```swift
// Aggregate stats
@FetchOne(
    Item.select {
        Stats.Columns(
            totalCount: $0.count(),
            completedCount: $0.count(filter: $0.isCompleted),
            overdueCount: $0.count(filter: $0.isPastDue)
        )
    }
)
var stats = Stats()

// Single record by ID
@FetchOne(Item.find(itemID))
var item: Item
```

**@Fetch** - Dynamic queries with `FetchKeyRequest`:

```swift
@Fetch(SearchRequest()) var searchResults = SearchRequest.Value()

struct SearchRequest: FetchKeyRequest {
    struct Value {
        var items: [Item] = []
        var totalCount = 0
    }

    let searchText: String

    func fetch(_ db: Database) throws -> Value {
        let query = Item.where {
            if !searchText.isEmpty {
                $0.title.contains(searchText)
            }
        }
        return try Value(
            items: query.order(by: \.title).fetchAll(db),
            totalCount: query.count().fetchOne(db) ?? 0
        )
    }
}

// Reload with new parameters
try await $searchResults.load(
    SearchRequest(searchText: newText),
    animation: .default
)
```

> **Gotcha:** `withAnimation { }` around database writes does **not** animate `@FetchAll` / `@FetchOne` changes. Always use the `animation:` parameter on the query declaration or `$property.load(...)` call. See [G13](#g13-withanimation-does-not-work-with-database-writes).

### 10.6 CRUD Operations

```swift
@Dependency(\.defaultDatabase) var database

// CREATE
try await database.write { db in
    try Item.insert {
        Item.Draft(title: "New item", listID: listID)
    }.execute(db)
}

// CREATE with upsert
try await database.write { db in
    try Item.upsert {
        Item.Draft(id: existingID, title: "Updated", listID: listID)
    }.execute(db)
}

// READ
let item = try await database.read { db in
    try Item.find(itemID).fetchOne(db)
}

// UPDATE specific fields
try await database.write { db in
    try Item.find(itemID)
        .update { $0.isCompleted = true }
        .execute(db)
}

// UPDATE with conditions
try await database.write { db in
    try Item
        .where { $0.listID.eq(listID) && !$0.isCompleted }
        .update { $0.isCompleted = true }
        .execute(db)
}

// DELETE
try await database.write { db in
    try Item.delete(item).execute(db)
}

// DELETE with conditions
try await database.write { db in
    try Item
        .where { $0.isCompleted }
        .delete()
        .execute(db)
}
```

### 10.7 Draft Types for Forms

The `@Table` macro auto-generates a `Draft` type for creating new records:

```swift
// Create empty draft
let draft = Item.Draft(listID: someListID)

// Create draft from existing record (for editing)
let draft = Item.Draft(existingItem)

// Use in SwiftUI forms
struct ItemFormView: View {
    @State var item: Item.Draft

    var body: some View {
        Form {
            TextField("Title", text: $item.title)
            TextEditor(text: $item.notes)
            Toggle("Completed", isOn: $item.isCompleted)
            Picker("Priority", selection: $item.priority) {
                Text("None").tag(Item.Priority?.none)
                Text("Low").tag(Item.Priority?.some(.low))
                Text("Medium").tag(Item.Priority?.some(.medium))
                Text("High").tag(Item.Priority?.some(.high))
            }
        }
    }
}
```

### 10.8 Relationships and Joins

#### One-to-Many (INNER JOIN)

Use `.join()` for INNER JOIN — only returns rows where the join condition matches in both tables:

```swift
@Selection
struct ItemWithList: Identifiable {
    var id: Item.ID { item.id }
    let item: Item
    let listTitle: String
}

@FetchAll(
    Item
        .join(ItemList.all) { $0.listID.eq($1.id) }
        .select {
            ItemWithList.Columns(
                item: $0,
                listTitle: $1.title
            )
        }
)
var itemsWithList
```

#### LEFT JOIN

Use `.leftJoin()` when the right table may not have a match (returns NULLs for non-matching rows):

```swift
@Selection
struct ListRow: Identifiable {
    var id: ItemList.ID { list.id }
    let list: ItemList
    let isShared: Bool
}

@FetchAll(
    ItemList
        .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
        .select {
            ListRow.Columns(
                list: $0,
                isShared: $1.isShared ?? false  // Default for NULL
            )
        }
)
var listRows
```

#### Many-to-Many Through Junction Tables

```swift
@Table
struct Tag: Identifiable {
    let id: UUID
    var title = ""
}

@Table
struct ItemTag: Identifiable {
    let id: UUID
    var itemID: Item.ID
    var tagID: Tag.ID
}
```

Query items with their tags using chained joins:

```swift
@Selection
struct TagWithCount: Identifiable {
    var id: String { tagTitle }
    let tagTitle: String
    let itemCount: Int
}

@FetchAll(
    Tag.group(by: \.primaryKey)
        .leftJoin(ItemTag.all) { $0.primaryKey.eq($1.tagID) }
        .leftJoin(Item.all) { $1.itemID.eq($2.id) }
        .having { $2.count().gt(0) }
        .select {
            TagWithCount.Columns(
                tagTitle: $0.title,
                itemCount: $2.count()
            )
        }
)
var tagsWithCounts
```

**Key points:**
- `$0`, `$1`, `$2` refer to the first, second, and third tables in the join chain
- `.group(by:)` is applied before joins
- `.having()` filters after grouping (like SQL `HAVING`)

#### Aggregation with @Selection and @FetchOne

```swift
@Selection
struct Stats {
    var totalCount = 0
    var completedCount = 0
    var flaggedCount = 0
    var todayCount = 0
}

@FetchOne(
    Item.select {
        Stats.Columns(
            totalCount: $0.count(),
            completedCount: $0.count(filter: $0.isCompleted),
            flaggedCount: $0.count(filter: $0.isFlagged && !$0.isCompleted),
            todayCount: $0.count(filter: $0.isToday)
        )
    }
)
var stats = Stats()
```

Simpler single-value aggregates:

```swift
@FetchOne(Item.count()) var totalCount = 0
@FetchOne(Item.where { !$0.isCompleted }.count()) var pendingCount = 0
```

### 10.9 Computed Query Expressions

Add computed properties to `TableColumns` for reusable query logic:

```swift
extension Item.TableColumns {
    var isPastDue: some QueryExpression<Bool> {
        @Dependency(\.date.now) var now
        return !isCompleted && #sql("coalesce(date(\(dueDate)) < date(\(now)), 0)")
    }

    var isToday: some QueryExpression<Bool> {
        @Dependency(\.date.now) var now
        return !isCompleted && #sql("coalesce(date(\(dueDate)) = date(\(now)), 0)")
    }
}
```

Use computed expressions in `@FetchAll`, `@FetchOne`, and `@Selection`:

```swift
// In @Selection
@FetchOne(
    Item.select {
        Stats.Columns(
            todayCount: $0.count(filter: $0.isToday),
            overdueCount: $0.count(filter: $0.isPastDue)
        )
    }
)
var stats = Stats()
```

#### Dynamic Date-Based Filtering

Use `#bind()` for dynamic values in queries:

```swift
@FetchAll(Item.none) var items

func updateQuery(filterDate: Date?, order: SortOrder) async {
    await withErrorReporting {
        try await $items.load(
            Item
                .where { $0.timestamp > #bind(filterDate ?? .distantPast) }
                .order {
                    if order == .forward { $0.timestamp }
                    else { $0.timestamp.desc() }
                }
                .limit(10)
        )
    }
}
```

### 10.10 Migrations

#### Rules

- Use GRDB's `DatabaseMigrator` with raw `#sql` strings
- **Do NOT** use GRDB's migration DSLs (`create(table:)`, `alter(table:)`) — use `#sql` instead
- **Never** edit existing migrations that have shipped to users
- Non-null columns added to existing tables **must** have a default with `NOT NULL ON CONFLICT REPLACE`
- Nullable columns do not need a default
- If using `SyncEngine`, **never** drop or rename columns/tables (backward compatibility)
- Migrate parent tables before child tables when changing primary keys

#### Create Tables

```swift
migrator.registerMigration("Create 'items' and 'itemLists'") { db in
    try #sql("""
        CREATE TABLE "itemLists" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
            "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        ) STRICT
        """).execute(db)

    try #sql("""
        CREATE TABLE "items" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
            "isCompleted" INTEGER NOT NULL DEFAULT 0,
            "listID" TEXT NOT NULL REFERENCES "itemLists"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

    try #sql("""
        CREATE INDEX "index_items_on_listID" ON "items"("listID")
        """).execute(db)
}
```

#### Add Columns

```swift
// Non-null column MUST have a default
migrator.registerMigration("Add 'priority' to 'items'") { db in
    try #sql("""
        ALTER TABLE "items"
        ADD COLUMN "priority" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """).execute(db)
}

// Nullable column — no default needed
migrator.registerMigration("Add 'dueDate' to 'items'") { db in
    try #sql("""
        ALTER TABLE "items"
        ADD COLUMN "dueDate" TEXT
        """).execute(db)
}
```

#### Data Migrations (Create-Copy-Drop-Rename)

For operations SQLite doesn't support directly (changing column types, adding primary keys, complex schema changes), use the 4-step pattern:

```swift
migrator.registerMigration("Convert 'items' primary key to UUID") { db in
    // 1. Create new table with desired schema
    try #sql("""
        CREATE TABLE "new_items" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
            "listID" TEXT NOT NULL REFERENCES "itemLists"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

    // 2. Copy and transform data
    try #sql("""
        INSERT INTO "new_items" ("id", "title", "listID")
        SELECT
            '00000000-0000-0000-0000-' || printf('%012x', "id"),
            "title",
            "listID"
        FROM "items"
        """).execute(db)

    // 3. Drop old table
    try #sql("""DROP TABLE "items" """).execute(db)

    // 4. Rename new table
    try #sql("""ALTER TABLE "new_items" RENAME TO "items" """).execute(db)
}
```

#### SQLite Migration Limitations

| Operation | Support | Workaround |
|---|---|---|
| Add column | Supported | `ALTER TABLE ... ADD COLUMN` |
| Drop column | SQLite 3.35.0+ only | Create-Copy-Drop-Rename |
| Rename column | SQLite 3.25.0+ | `ALTER TABLE ... RENAME COLUMN` |
| Change column type | Not supported | Create-Copy-Drop-Rename |
| Add/change primary key | Not supported | Create-Copy-Drop-Rename |
| Change foreign keys | Not supported | Create-Copy-Drop-Rename |
| Rename table | Supported | `ALTER TABLE ... RENAME TO` |

### 10.11 iCloud Sync with SyncEngine

#### Entitlements Setup

1. Add iCloud entitlement with CloudKit
2. Add Background Modes capability with "Remote notifications"
3. Add `CKSharingSupported = true` to Info.plist (for sharing)
4. Deploy the iCloud container schema before shipping

#### Full SyncEngine Setup

```swift
extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.attachMetadatabase()  // Required for CloudKit metadata
            db.add(function: $uuid)      // Controllable UUID generation
        }

        let database = try SQLiteData.defaultDatabase(configuration: configuration)

        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        // ... register migrations ...
        try migrator.migrate(database)

        defaultDatabase = database
        defaultSyncEngine = try SyncEngine(
            for: database,
            tables: ItemList.self, Item.self, Tag.self, ItemTag.self,
            privateTables: ItemListPrivate.self  // Not shared with other users
        )
    }
}
```

**SyncEngine init parameters:**
- `tables:` — Tables to sync to CloudKit (explicit opt-in)
- `privateTables:` — Synced but NOT shared when a parent record is shared
- `containerIdentifier:` — Custom CloudKit container (defaults to app's primary)
- `startsImmediately:` — Set `false` to make sync opt-in (e.g., for in-app purchase)
- `delegate:` — Custom event handling

#### Sharing Records

```swift
import CloudKit
import SQLiteData

struct ItemListView: View {
    let itemList: ItemList
    @Dependency(\.defaultSyncEngine) var syncEngine
    @State var sharedRecord: SharedRecord?

    var body: some View {
        Form { /* ... */ }
        .toolbar {
            Button("Share") {
                Task {
                    await withErrorReporting {
                        sharedRecord = try await syncEngine.share(record: itemList) { share in
                            share[CKShare.SystemFieldKey.title] = itemList.title
                        }
                    }
                }
            }
        }
        .sheet(item: $sharedRecord) { sharedRecord in
            CloudSharingView(sharedRecord: sharedRecord)
        }
    }
}
```

**Sharing rules:**
- Only root records (no foreign keys) can be shared
- Associated records are shared if they have a single foreign key and are not in `privateTables`
- Many-to-many junction tables (multiple foreign keys) **cannot** be shared

#### Accepting Shares

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    @Dependency(\.defaultSyncEngine) var syncEngine

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { try await syncEngine.acceptShare(metadata: metadata) }
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options options: UIScene.ConnectionOptions
    ) {
        guard let metadata = options.cloudKitShareMetadata else { return }
        Task { try await syncEngine.acceptShare(metadata: metadata) }
    }
}
```

#### Checking Permissions

```swift
// Check if record is shared
let isShared = try await database.read { db in
    SyncMetadata
        .find(itemList.syncMetadataID)
        .select(\.isShared)
        .fetchOne(db) ?? false
}

// Check write permission before allowing edits
let share = try await database.read { db in
    SyncMetadata
        .find(itemList.syncMetadataID)
        .select(\.share)
        .fetchOne(db) ?? nil
}
guard share?.currentUserParticipant?.permission == .readWrite
    || share?.publicPermission == .readWrite
else {
    // User cannot write to this record
    return
}

// Handle permission errors on write
do {
    try await database.write { db in
        try Item.find(id).update { $0.title = "New" }.execute(db)
    }
} catch let error as DatabaseError where error.message == SyncEngine.writePermissionError {
    // Show permission denied alert
}
```

#### Sync Limitations

- Compound primary keys are not supported
- Unique indexes are not supported (besides primary keys)
- Avoid reserved iCloud column names: `creationDate`, `creatorUserRecordID`, `etag`, `modificationDate`, `recordID`, `recordType`

### 10.12 Testing Patterns

#### Suite-Level Database Bootstrap

```swift
import DependenciesTestSupport
import SQLiteData
import Testing

@MainActor
@Suite(
    .dependencies {
        $0.uuid = .incrementing
        try $0.bootstrapDatabase()
    }
)
struct ItemTests {
    @Dependency(\.defaultDatabase) var database
}
```

**Important:** Use `try` (not `try!`) in test traits — they have a throwing context.

#### Controllable UUID Generation

For primary-keyed tables using `DEFAULT uuid()`, override the database function:

```swift
// 1. Declare custom database function
@DatabaseFunction nonisolated func uuid() -> UUID {
    @Dependency(\.uuid) var uuid
    return uuid()
}

// 2. Install in prepareDatabase
configuration.prepareDatabase { db in
    db.add(function: $uuid)
}

// 3. Use .incrementing in tests
@Suite(.dependency(\.uuid, .incrementing))
```

#### Seeding Test Data

Use negative integer UUIDs for seeds to avoid clashing with feature-generated UUIDs:

```swift
@Suite(
    .dependencies {
        $0.uuid = .incrementing
        try $0.bootstrapDatabase()
        try $0.defaultDatabase.write { db in
            try db.seed {
                ItemList(id: UUID(-1), title: "Personal")
                Item(id: UUID(-1), title: "Buy milk", listID: UUID(-1))
                Item(id: UUID(-2), title: "Walk dog", listID: UUID(-1))

                ItemList(id: UUID(-2), title: "Work")
                Item(id: UUID(-3), title: "Call client", listID: UUID(-2))
            }
        }
    }
)
struct ItemTests { /* ... */ }
```

**Rules:**
- Each seeded model gets an ID one *less* than the lowest for that type
- **Do NOT** share seeds with Xcode previews — tests have their own seeds
- **Do NOT** use `Draft` in tests — use the model type directly with explicit IDs

#### Testing CRUD Operations

```swift
extension ItemTests {
    @Test
    func createItem() async throws {
        try await database.write { db in
            try Item.insert {
                Item.Draft(title: "New item", listID: UUID(-1))
            }.execute(db)
        }

        let count = try await database.read { db in
            try Item.where { $0.listID.eq(UUID(-1)) }.fetchCount(db)
        }
        #expect(count == 3)  // 2 seeded + 1 new
    }

    @Test
    func updateItem() async throws {
        try await database.write { db in
            try Item.find(UUID(-1))
                .update { $0.isCompleted = true }
                .execute(db)
        }

        let item = try await database.read { db in
            try Item.find(UUID(-1)).fetchOne(db)
        }
        #expect(item?.isCompleted == true)
    }

    @Test
    func deleteCompletedItems() async throws {
        try await database.write { db in
            try Item.find(UUID(-1))
                .update { $0.isCompleted = true }
                .execute(db)
        }

        try await database.write { db in
            try Item.where { $0.isCompleted }.delete().execute(db)
        }

        let remaining = try await database.read { db in
            try Item.fetchCount(db)
        }
        #expect(remaining == 2)
    }
}
```

#### Testing with expectNoDifference

```swift
import CustomDump

@Test
func fetchItemsForList() async throws {
    let items = try await database.read { db in
        try Item
            .where { $0.listID.eq(UUID(-1)) }
            .order { $0.title }
            .fetchAll(db)
    }

    expectNoDifference(items, [
        Item(id: UUID(-1), title: "Buy milk", listID: UUID(-1)),
        Item(id: UUID(-2), title: "Walk dog", listID: UUID(-1)),
    ])
}
```

#### Xcode Preview Seeding

```swift
#Preview {
    let _ = prepareDependencies {
        try! $0.bootstrapDatabase()
        try! $0.defaultDatabase.write { db in
            try db.seed {
                ItemList(id: UUID(1), title: "Personal")
                Item(id: UUID(1), title: "Buy milk", listID: UUID(1))
            }
        }
    }
    ItemListView()
}
```

**Preview rules:**
- Use `try!` (previews are not a throwing context)
- Use positive integer UUIDs (opposite of tests)
- **Never** use `Draft` in `#Preview` — the macro can't see generated Draft types

---

## 11. Naming Conventions

### Complete Reference Table

| Element | Convention | Example |
|---|---|---|
| **Feature struct** | PascalCase + `Feature` suffix | `ProfileFeature` |
| **Feature file** | Same as struct | `ProfileFeature.swift` |
| **View struct** | PascalCase + `View` suffix | `ProfileView` |
| **View file** | Same as struct (or `Screen` suffix) | `ProfileView.swift`, `ProfileScreen.swift` |
| **Router struct** | PascalCase + `Router` suffix | `ProfileRouter` |
| **State** | Nested in feature, `State` | `ProfileFeature.State` |
| **Action** | Nested in feature, `Action` | `ProfileFeature.Action` |
| **View actions** | Past tense verb + noun | `saveButtonTapped`, `itemSwiped` |
| **Internal actions** | Noun + response/result | `dataResponse(Result<...>)`, `timerFired` |
| **Delegate actions** | `did` + verb or request noun | `didComplete`, `editRequested` |
| **Handler properties** | `handle` + category + `Actions` | `handleViewActions`, `handleInternalActions` |
| **Client struct** | PascalCase + `Client` suffix | `ItemClient` |
| **Client file** | Struct name | `ItemClient.swift` |
| **Client live file** | Struct name + `+Live` | `ItemClient+Live.swift` |
| **Endpoints** | PascalCase + `Endpoint(s)` | `ItemEndpoints.swift` |
| **Dependency accessor** | camelCase | `\.itemClient` |
| **@Table model** | PascalCase, singular | `Item`, `ItemList` |
| **Database table** | camelCase, plural | `"items"`, `"itemLists"` |
| **Bool properties** | `is`/`has` prefix | `isLoading`, `hasChanges` |
| **Optional state** | Descriptive, no `optional` prefix | `selectedItem: Item?` |
| **Extensions file** | Type + `+` | `String+.swift`, `Date+.swift` |
| **MARK comments** | `// MARK: - Section Name` | `// MARK: - Handlers` |

---

## 12. Code Style

### Import Organization

Imports must be **alphabetically ordered**. Enforce with SwiftLint's `sorted_imports` rule.

```swift
// CORRECT
import ComposableArchitecture
import Foundation
import Models
import Networking
import SwiftUI
import Utilities

// INCORRECT
import SwiftUI
import Foundation
import ComposableArchitecture
```

### Access Control

| Context | Default Access |
|---|---|
| Package-level types (features, clients) | `public` |
| State properties | `var` (internal, observable) |
| Handler computed properties | `private` |
| Helper methods | `private` |
| View subview properties | `private` |
| Extensions on existing types | `public` if in a package, otherwise internal |

### MARK Comments

Use `// MARK: -` to organize sections within files:

```swift
// MARK: - State
// MARK: - Action
// MARK: - Dependencies
// MARK: - Reducer
// MARK: - Handlers
// MARK: - Sections (in views)
// MARK: - Helpers
// MARK: - Alert States
// MARK: - Dependency Key
```

### Documentation Comments

Use `///` for single-line documentation:

```swift
/// Whether the profile is currently loading data from the server.
var isLoading = false
```

Use `/** */` for multi-line documentation:

```swift
/**
 Handles all view-triggered actions from the settings screen.

 This handler processes direct user interactions and translates them
 into internal actions or delegate effects as appropriate.
 */
private var handleViewActions: ReduceChild<State, Action, Action.View> { ... }
```

### Color Management

Always use **Xcode's built-in asset catalog** for colors. Only create `Color` extensions when adding functionality beyond asset lookup.

```swift
// CORRECT - Colors defined in Assets.xcassets
Color("primaryBackground")
Color(.primaryBackground)  // With type-safe extension from asset catalog

// ONLY when adding functionality
extension Color {
    /// Converts a hex string to a Color
    init(hex: String) { ... }
}

// INCORRECT - Don't define palette colors in code
extension Color {
    static let primaryBackground = Color(red: 0.95, green: 0.95, blue: 0.97)
}
```

### Alphabetize Everything

- Import statements
- Action enum cases (both top-level and nested)
- State properties (logical grouping allowed, alphabetical within groups)
- Handler computed properties in the reducer body
- Switch cases (within reason - group related cases)

---

## 13. Testing

### Apple Testing Framework

Use Swift Testing (`@Suite`, `@Test`, `#expect`) instead of XCTest:

```swift
import ComposableArchitecture
import Testing

@MainActor
@Suite
struct ProfileFeatureTests {

    @Test("Profile loads on appear")
    func profileLoadsOnAppear() async {
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.profileClient.fetch = { _ in .sample }
        }

        await store.send(.view(.onAppear)) {
            $0.isLoading = true
        }

        await store.receive(\.internal.profileResponse.success) {
            $0.isLoading = false
            $0.displayName = "Sample Name"
        }
    }

    @Test("Delete shows confirmation alert")
    func deleteShowsAlert() async {
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        }

        await store.send(.view(.deleteButtonTapped)) {
            $0.alert = AlertState {
                TextState("Delete Profile?")
            } actions: {
                ButtonState(role: .destructive, action: .confirmDeleteTapped) {
                    TextState("Delete")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
    }
}
```

### Dependencies Test Trait (Preferred)

Use the `.dependencies {}` test trait to configure shared dependencies for an entire suite. This is preferred over `withDependencies` on each test because it reduces duplication and makes the suite's requirements explicit.

> **Gotcha:** Always override `\.continuousClock` with `ImmediateClock()` or `TestClock()` in tests — accessing it without an override triggers "Unimplemented" failures. See [G14](#g14-continuousclock-not-overridden-in-tests).

```swift
@MainActor
@Suite(
    .dependencies {
        $0.continuousClock = ImmediateClock()
        $0.date.now = Date(timeIntervalSince1970: 1_000_000)
        $0.uuid = .incrementing
    }
)
struct ItemFeatureTests {
    @Test
    func createItem() async {
        // All tests in this suite share the above dependencies
        let store = TestStore(initialState: ItemFeature.State()) {
            ItemFeature()
        } withDependencies: {
            // Override specific dependencies per-test
            $0.itemClient.create = { draft in
                Item(id: UUID(), title: draft.title)
            }
        }
        // ...
    }
}
```

### Testing Shared State

```swift
@Test
func incrementSharedCount() async {
    let store = TestStore(
        initialState: CounterFeature.State(count: Shared(0))
    ) {
        CounterFeature()
    }

    await store.send(.view(.incrementButtonTapped)) {
        $0.$count.withLock { $0 = 1 }
    }
}
```

### Non-Exhaustive Testing

Use `exhaustivity = .off` when you only want to assert specific state changes:

```swift
@Test
func analyticsTracking() async {
    let collector = AnalyticsCollector()

    let store = TestStore(initialState: Feature.State()) {
        Feature()
    } withDependencies: {
        $0.analyticsClient.send = { event in
            await collector.collect(event)
        }
    }

    store.exhaustivity = .off

    await store.send(.view(.buttonTapped))

    let events = await collector.events
    #expect(events.count == 1)
}
```

### App Entry Point Guard

Your app entry point boots alongside tests in the simulator. Guard against it to prevent unintended side effects. See [G15](#g15-application-code-running-during-tests).

```swift
@main
struct MyApp: App {
    init() {
        guard !_XCTIsTesting else { return }
        prepareDependencies { try! $0.bootstrapDatabase() }
    }
}
```

### CustomDump Assertions

Use `expectNoDifference` and `expectDifference` from the CustomDump library for detailed failure messages:

```swift
import CustomDump

@Test
func stateTransition() {
    var state = Feature.State()
    state.name = "Updated"

    expectNoDifference(state, Feature.State(name: "Updated"))
}
```

---

## 14. Common Gotchas & Pitfalls

A catalog of mistakes that are easy to make and hard to debug. Each gotcha is marked with a severity and includes inline code examples. Every gotcha is also cross-referenced at the relevant location in earlier sections (look for `> **Gotcha:**` callouts).

### G1. Never Send Child Actions Directly from a Parent

**Severity: High**

Sending a child feature's action directly from a parent reducer breaks encapsulation and creates tight coupling. The child becomes impossible to refactor without updating every parent that sends its actions.

```swift
// WRONG: Parent sending child action directly
case .view(.refreshTapped):
    return .send(.child(.internal(.fetchData)))  // Breaks encapsulation!

// CORRECT: Use the delegate pattern
// In child:
case .view(.refreshTapped):
    return .send(.delegate(.refreshRequested))

// In parent:
case .child(.delegate(.refreshRequested)):
    return .send(.internal(.fetchData))
```

**Rule:** Parents observe child delegate actions. Parents never reach into a child's `.view` or `.internal` actions.

### G2. Missing BindingReducer

**Severity: High**

If your `Action` conforms to `BindableAction`, you **must** include `BindingReducer()` at the top of your reducer body. Without it, bindings silently fail — views show stale data and you get purple runtime warnings.

```swift
// WRONG: Missing BindingReducer
var body: some ReducerOf<Self> {
    Reduce { state, action in ... }
}

// CORRECT: BindingReducer at the top
var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in ... }
}
```

### G3. Missing `.ifLet` / `.forEach` Reducer Composition

**Severity: High**

Adding `@Presents` state and `PresentationAction` to your domain but forgetting to compose `.ifLet` or `.forEach` means the child reducer never runs. The view may appear, but no child logic executes.

```swift
// WRONG: Navigation state but no composition
var body: some ReducerOf<Self> {
    Reduce { state, action in ... }
    // Missing: .ifLet(\.$destination, action: \.destination)
}

// CORRECT: Always pair navigation state with its operator
var body: some ReducerOf<Self> {
    Reduce { state, action in ... }
    .ifLet(\.$destination, action: \.destination)
    .forEach(\.path, action: \.path)
}
```

### G4. State Mutation Inside Effects

**Severity: High**

TCA state is value-type and must only be mutated synchronously inside the reducer. Capturing `state` in an effect closure captures a copy — mutations are silently lost.

```swift
// WRONG: Mutating captured state in effect
case .view(.loadTapped):
    return .run { _ in
        let data = try await apiClient.fetch()
        state.items = data  // Compiler error or silent no-op
    }

// CORRECT: Send result back as an action
case .view(.loadTapped):
    return .run { send in
        let result = await Result { try await apiClient.fetch() }
        await send(.internal(.fetchResponse(result)))
    }

case .internal(.fetchResponse(.success(let data))):
    state.items = data
    return .none
```

### G5. Long-Running Effects Without Cancellation

**Severity: High**

Timers, WebSocket connections, and `AsyncStream` subscriptions that aren't cancelled leak memory and cause `TestStore` to fail with "An effect returned for this action is still running."

```swift
enum CancelID { case timer }

case .view(.onAppear):
    return .run { send in
        for await _ in clock.timer(interval: .seconds(1)) {
            await send(.internal(.timerTick))
        }
    }
    .cancellable(id: CancelID.timer)

case .view(.onDisappear):
    return .cancel(id: CancelID.timer)

// In tests:
let task = await store.send(.view(.onAppear))
// ... assertions ...
await task.cancel()
```

**Note:** Make cancellation ID enums `internal` (not `private`). Private nested enums may be optimized away in Release builds, silently breaking cancellation.

### G6. Action Ping-Pong

**Severity: Medium**

Two features sending actions back and forth to each other, creating circular dependencies. Feature A sends to Feature B which sends back to Feature A.

```swift
// WRONG: Circular action flow
// Parent receives child delegate, sends action to another child,
// which delegates back to parent, which sends to first child...

// CORRECT: Coordinate in the parent reducer
case .childA(.delegate(.dataReady(let data))):
    state.childB.data = data  // Direct state mutation, no ping-pong
    return .none
```

### G7. `@Shared` Reference Semantics Surprise

**Severity: Medium**

`@Shared` state has reference semantics and can be mutated from effects without sending actions. This bypasses TCA's unidirectional data flow.

```swift
// @Shared can be mutated directly in effects
case .view(.logoutTapped):
    return .run { [session = state.$userSession] _ in
        session.withLock { $0 = nil }  // No action needed
    }

// Testing requires asserting on shared state changes explicitly
await store.send(.view(.logoutTapped))
// TestStore detects the shared state change
```

Use `@Shared` sparingly and intentionally. Always use `$shared.withLock { }` for thread-safe mutations from effects. See also the inline note in [Section 8](#8-state-management).

### G8. High-Frequency Actions

**Severity: Medium**

Sending dozens of actions per second (scroll offsets, drag gestures) is expensive because every action passes through the entire reducer hierarchy.

```swift
// WRONG: Action on every scroll frame
.onScrollGeometryChange(of: \.contentOffset) { _, new in
    store.send(.scrollOffsetChanged(new))  // 60+ actions/second
}

// CORRECT: Debounce or keep local
case .internal(.scrollOffsetChanged(let offset)):
    state.scrollOffset = offset
    return .run { send in
        try await clock.sleep(for: .milliseconds(200))
        await send(.internal(.scrollSettled))
    }
    .cancellable(id: CancelID.scroll, cancelInFlight: true)
```

### G9. `cancelInFlight` with Reused Reducers

**Severity: Medium**

Using a static cancellation ID with `cancelInFlight: true` in a reducer composed via `.forEach` cancels the first instance's effect when the second appears.

```swift
// WRONG: Shared ID across instances
.cancellable(id: CancelID.loadItem, cancelInFlight: true)

// CORRECT: Unique ID per instance
.cancellable(id: state.id, cancelInFlight: true)
```

### G10. Binding.init(get:set:) Bypasses TCA

**Severity: Medium**

Using `Binding(get:set:)` to create bindings to store state bypasses TCA's state management and causes subtle bugs. Always use `$store.property` with `@Bindable`.

### G11. `willSet` / `didSet` in State Causes Infinite Loops

**Severity: High**

Property observers in `@ObservableState` structs interact with observation tracking and can cause infinite re-render loops.

```swift
// WRONG: Property observer in State
@ObservableState
struct State: Equatable {
    var count: Int = 0 {
        didSet { derivedValue = count * 2 }  // Infinite loop risk
    }
}

// CORRECT: Handle derived state in the reducer
case .binding(\.count):
    state.derivedValue = state.count * 2
    return .none
```

### G12. NavigationLink(state:) with Dependencies

**Severity: Medium**

Constructing child state in `NavigationLink(state:)` happens in the view layer where dependencies may not be wired correctly. Construct navigation state in the reducer instead.

```swift
// WRONG: State construction in view
NavigationLink(state: ChildFeature.State(userID: store.userID)) {
    Text("Go")
}

// CORRECT: Send action, construct state in reducer
Button("Go") { store.send(.view(.childButtonTapped)) }

// In reducer:
case .view(.childButtonTapped):
    state.path.append(.child(ChildFeature.State(userID: state.userID)))
    return .none
```

### G13. `withAnimation` Does Not Work with Database Writes

**Severity: Medium** (SQLiteData-specific)

`withAnimation` around database inserts, updates, and deletes does **not** animate `@FetchAll` / `@FetchOne` changes. Use the `animation:` parameter instead.

```swift
// WRONG: withAnimation has no effect on database observation
try withAnimation {
    try database.write { db in
        try Item.find(id).delete().execute(db)  // No animation
    }
}

// CORRECT: Use the animation parameter on @FetchAll
@FetchAll(animation: .default) var items: [Item]

// Or on dynamic queries
try await $items.load(
    Item.where(\.isCompleted),
    animation: .default
)
```

### G14. ContinuousClock Not Overridden in Tests

**Severity: Medium**

Accessing `\.continuousClock` without overriding it in tests triggers "Unimplemented" failures. Always provide `ImmediateClock()` or `TestClock()`.

```swift
@Suite(
    .dependencies {
        $0.continuousClock = ImmediateClock()
    }
)
struct MyFeatureTests { /* ... */ }
```

### G15. Application Code Running During Tests

**Severity: Medium**

Your app entry point boots alongside tests in the simulator. Guard against it:

```swift
@main
struct MyApp: App {
    init() {
        guard !_XCTIsTesting else { return }
        prepareDependencies { try! $0.bootstrapDatabase() }
    }
    var body: some Scene {
        WindowGroup {
            if _XCTIsTesting {
                EmptyView()
            } else {
                AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
            }
        }
    }
}
```

### G16. Capture State Values in Effect Closures

**Severity: Medium**

Capturing `state` directly in `Effect.run` closures triggers Sendable warnings. Capture only the specific values you need.

```swift
// WRONG: Captures non-Sendable state
return .run { send in
    let result = try await apiClient.fetch(state.userID)
}

// CORRECT: Capture in closure capture list
return .run { [userID = state.userID] send in
    let result = try await apiClient.fetch(userID)
    await send(.internal(.fetchResponse(result)))
}
```

---

## 15. Extensions Starter Kit

A curated list of extensions useful for bootstrapping new TCA/SwiftUI projects. Organized by type.

### View Extensions

```swift
// MARK: - Loading Overlay

extension View {
    /// Overlays a loading spinner with dimmed background
    func loadingOverlay(isLoading: Bool) -> some View {
        overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Skeleton / Shimmer Effect

extension View {
    /// Applies a shimmer animation for loading states
    func shimmering(active: Bool = true, intensity: Double = 0.5) -> some View {
        modifier(ShimmeringModifier(active: active, intensity: intensity))
    }
}

struct ShimmeringModifier: ViewModifier {
    let active: Bool
    let intensity: Double
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(intensity),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = UIScreen.main.bounds.width
                        }
                    }
                }
            }
            .clipped()
    }
}

// MARK: - Press Effect

extension View {
    /// Scales and fades on press for tactile feedback
    func pressEffect(isPressed: Bool) -> some View {
        scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
    }
}

// MARK: - Card Styling

extension View {
    /// Standard card with border
    func cardStyle(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        borderColor: Color = .gray.opacity(0.2),
        backgroundColor: Color = .white
    ) -> some View {
        self.padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    /// Card with shadow elevation
    func elevatedCardStyle(
        elevation: CGFloat = 4,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        backgroundColor: Color = .white
    ) -> some View {
        self.padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.1), radius: elevation, y: elevation / 2)
    }
}

// MARK: - Field Styling

extension View {
    /// Standard form field appearance with focus/error states
    func fieldStyle(isError: Bool = false, isFocused: Bool = false) -> some View {
        self.padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isError ? Color.red : isFocused ? Color.accentColor : Color.clear,
                        lineWidth: isError || isFocused ? 1.5 : 0
                    )
            )
    }
}

// MARK: - Separator

extension View {
    /// Adds a separator line at the specified edge
    func separator(
        edge: Edge = .bottom,
        color: Color = Color(.separator),
        thickness: CGFloat = 0.5,
        padding: CGFloat = 0
    ) -> some View {
        overlay(alignment: edge.alignment) {
            Rectangle()
                .fill(color)
                .frame(
                    width: edge.isHorizontal ? thickness : nil,
                    height: edge.isVertical ? thickness : nil
                )
                .padding(edge.isHorizontal ? .vertical : .horizontal, padding)
        }
    }
}

private extension Edge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    var isHorizontal: Bool { self == .leading || self == .trailing }
    var isVertical: Bool { self == .top || self == .bottom }
}

// MARK: - Keyboard Dismissal

extension View {
    /// Dismisses the keyboard when tapping outside of text fields
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }
}

// MARK: - Conditional Modifier

extension View {
    /// Applies a modifier conditionally
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - On First Appear

extension View {
    /// Executes an action only the first time the view appears
    func onFirstAppear(_ action: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(action: action))
    }
}

private struct OnFirstAppearModifier: ViewModifier {
    let action: () -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}

// MARK: - Fade Overlay

extension View {
    /// Adds a fade gradient at the specified edge
    func fadeOverlay(
        edge: VerticalEdge = .bottom,
        color: Color = .white,
        distance: CGFloat = 40
    ) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            LinearGradient(
                colors: [color, color.opacity(0)],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
            .frame(height: distance)
            .allowsHitTesting(false)
        }
    }
}
```

### String Extensions

```swift
extension String {
    /// Returns true if string is empty or contains only whitespace
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns a trimmed version of the string
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Masks an email for display (e.g., "j*****@gmail.com")
    func maskEmail() -> String {
        guard let atIndex = firstIndex(of: "@") else { return self }
        let username = self[startIndex..<atIndex]
        guard username.count > 1 else { return self }
        let first = String(username.prefix(1))
        let domain = String(self[atIndex...])
        let masked = String(repeating: "*", count: min(username.count - 1, 5))
        return first + masked + domain
    }

    /// Masks a phone number for display (e.g., "(***) *** - 7890")
    func maskPhone() -> String {
        let digits = filter(\.isNumber)
        guard digits.count >= 4 else { return self }
        let last4 = String(digits.suffix(4))
        return "(***) *** - \(last4)"
    }

    /// URL-encodes the string
    var urlEncoded: String? {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
}
```

### Date Extensions

```swift
extension Date {
    // MARK: - Manipulation

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    func adding(hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self) ?? self
    }

    // MARK: - Comparison

    func isToday() -> Bool {
        Calendar.current.isDateInToday(self)
    }

    func isInSameMonth(as date: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: date, toGranularity: .month)
    }

    func isInSameYear(as date: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: date, toGranularity: .year)
    }

    // MARK: - Boundaries

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }

    var endOfMonth: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth) ?? self
    }

    // MARK: - Formatting

    /// Convert to string with custom format
    static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Parse from string with custom format
    static func date(from string: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.date(from: string)
    }
}
```

### DateFormatter Extensions

```swift
extension DateFormatter {
    /// Creates a formatter with a custom format string
    static func withFormat(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }

    /// Creates a formatter with date and time styles
    static func withStyles(
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style = .none
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }

    /// "M/d/yyyy"
    static let standard = withFormat("M/d/yyyy")

    /// "yyyy-MM-dd"
    static let iso8601 = withFormat("yyyy-MM-dd")

    /// "HH:mm:ss"
    static let time = withFormat("HH:mm:ss")
}
```

### Number Extensions

```swift
extension Double {
    /// Formats as currency string (e.g., "$42.90")
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}

extension Decimal {
    /// Formats as currency string
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
}
```

### Collection Extensions

```swift
extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Collection {
    /// Splits collection into chunks of the given size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[index(startIndex, offsetBy: $0)..<index(startIndex, offsetBy: Swift.min($0 + size, count))])
        }
    }
}

extension Sequence where Element: Hashable {
    /// Returns array with duplicates removed, preserving order
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```

### Optional Extensions

```swift
extension Optional where Wrapped == String {
    /// Returns the wrapped string, or empty string if nil
    var orEmpty: String {
        self ?? ""
    }
}

extension Optional {
    /// Returns true if the optional is nil
    var isNil: Bool { self == nil }

    /// Returns true if the optional is not nil
    var isNotNil: Bool { self != nil }
}
```

### Encodable Extensions

```swift
extension Encodable {
    /// Convert to Data (throws)
    func toData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Convert to JSON string (throws)
    func toJSONString() throws -> String {
        let data = try toData()
        return String(decoding: data, as: UTF8.self)
    }

    /// Convert to pretty-printed JSON string (throws)
    func toPrettyJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// Convert to dictionary (throws)
    func toDictionary() throws -> [String: Any] {
        let data = try toData()
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Safe version - returns nil on failure
    var asData: Data? { try? toData() }
    var asJSONString: String? { try? toJSONString() }
    var asDictionary: [String: Any]? { try? toDictionary() }
}
```

### URL Extensions

```swift
extension URL {
    /// User's documents directory
    static var documentsPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Documents directory with appended path component
    static func documentsPath(for key: String) -> URL {
        documentsPath.appendingPathComponent(key)
    }
}
```

### EdgeInsets Extensions

```swift
extension EdgeInsets {
    /// All edges set to zero
    static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// Uniform padding on all edges
    init(all value: CGFloat) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }

    /// Horizontal and vertical padding
    init(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}
```

### Task Extensions

```swift
extension Task where Success == Never, Failure == Never {
    /// Sleep for a Duration (convenience wrapper)
    static func sleep(for duration: Duration) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration.components.seconds * 1_000_000_000
            + duration.components.attoseconds / 1_000_000_000))
    }
}
```

### Result Extensions

```swift
extension Result {
    /// Returns the success value, or nil if failure
    var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// Returns the failure error, or nil if success
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    /// Returns true if the result is a success
    var isSuccess: Bool { success != nil }

    /// Returns true if the result is a failure
    var isFailure: Bool { failure != nil }
}
```

### CaseIterable Extensions

```swift
extension CaseIterable {
    /// All cases as an Array (useful when you need index-based access)
    static var allCasesArray: [Self] {
        Array(allCases)
    }
}
```

### Dictionary Extensions

```swift
extension Dictionary {
    /// Transforms dictionary keys while preserving values
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        reduce(into: [:]) { result, pair in
            result[transform(pair.key)] = pair.value
        }
    }
}
```

### Accessibility Extensions

```swift
extension View {
    /// Configures accessibility for a button
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .if(hint != nil) { view in
                view.accessibilityHint(hint!)
            }
    }

    /// Configures accessibility for an image
    func accessibleImage(description: String, isDecorative: Bool = false) -> some View {
        if isDecorative {
            return AnyView(accessibilityHidden(true))
        }
        return AnyView(accessibilityLabel(description).accessibilityAddTraits(.isImage))
    }
}
```

### UIApplication Extensions

```swift
extension UIApplication {
    /// Dismiss the keyboard
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
```

### KeyedDecodingContainer Extensions

```swift
extension KeyedDecodingContainer {
    /// Decodes an ISO8601 date, handling fractional seconds
    func decodeISO8601Date(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Cannot decode ISO8601 date from: \(string)"
        )
    }
}
```

### Color Extensions

```swift
// MARK: - Hex Initialization

extension Color {
    /// Initialize from hex string (supports 3, 6, or 8 character hex)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Brightness & Contrast

extension Color {
    /// Returns a lighter version of the color
    func lighter(by percentage: Double = 0.1) -> Color {
        adjustBrightness(by: abs(percentage))
    }

    /// Returns a darker version of the color
    func darker(by percentage: Double = 0.1) -> Color {
        adjustBrightness(by: -abs(percentage))
    }

    /// Whether the color is perceived as light
    var isLight: Bool {
        UIColor(self).relativeLuminance > 0.5
    }

    /// Returns black or white depending on which contrasts best
    var bestTextColor: Color {
        isLight ? .black : .white
    }

    private func adjustBrightness(by amount: Double) -> Color {
        guard let components = UIColor(self).hsba else { return self }
        return Color(hue: components.hue, saturation: components.saturation,
                     brightness: min(max(components.brightness + amount, 0), 1),
                     opacity: components.alpha)
    }
}
```

### Int Extensions

```swift
// MARK: - Ordinal String

extension Int {
    /// Returns ordinal string (1st, 2nd, 3rd, etc.)
    var ordinalString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Abbreviated Format

extension Int {
    /// Abbreviates large numbers (1K, 1.5M, 2.3B)
    var abbreviated: String {
        self.formatted(.number.notation(.compactName))
    }
}

// MARK: - Duration Formatting

extension Int {
    /// Formats seconds as mm:ss or h:mm:ss
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Time interval helpers
    var seconds: TimeInterval { TimeInterval(self) }
    var minutes: TimeInterval { TimeInterval(self) * 60 }
    var hours: TimeInterval { TimeInterval(self) * 3600 }
    var days: TimeInterval { TimeInterval(self) * 86400 }
}
```

### Comparable Extensions

```swift
extension Comparable {
    /// Clamps value to a closed range
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }

    /// Returns true if value is within the given range
    func isWithin(_ range: ClosedRange<Self>) -> Bool {
        range.contains(self)
    }
}
```

### Bundle Extensions

```swift
extension Bundle {
    /// Marketing version (e.g. "2.1.0")
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number (e.g. "142")
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Combined version string (e.g. "2.1.0 (142)")
    var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }

    /// App display name
    var displayName: String {
        infoDictionary?["CFBundleDisplayName"] as? String
            ?? infoDictionary?["CFBundleName"] as? String
            ?? "Unknown"
    }
}
```

### Data Extensions

```swift
extension Data {
    /// Hexadecimal string representation
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Pretty-printed JSON string (for debugging)
    var prettyPrintedJSON: String {
        guard let obj = try? JSONSerialization.jsonObject(with: self),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return String(data: self, encoding: .utf8) ?? "Unable to decode"
        }
        return str
    }

    /// Human-readable file size (e.g. "1.4 MB")
    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
```

### String Extensions (Additional)

```swift
extension String {
    /// Returns the initials from the string (e.g. "John Doe" -> "JD")
    var initials: String {
        split(separator: " ")
            .compactMap { $0.first.map(String.init) }
            .prefix(2)
            .joined()
            .uppercased()
    }

    /// Word count
    var wordCount: Int {
        split(separator: " ").count
    }

    /// Truncates to max length with ellipsis
    func truncated(to maxLength: Int, trailing: String = "...") -> String {
        count > maxLength ? String(prefix(maxLength)) + trailing : self
    }

    /// Whether the string contains only digits
    var containsOnlyDigits: Bool {
        !isEmpty && allSatisfy(\.isNumber)
    }

    /// Tests against a regular expression pattern
    func matches(pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    /// Capitalizes just the first letter
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }

    /// Converts "camelCase" to "snake_case"
    var snakeCased: String {
        let pattern = "([a-z0-9])([A-Z])"
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "$1_$2") }?
            .lowercased() ?? lowercased()
    }
}
```

### Date Extensions (Additional)

```swift
extension Date {
    /// Relative time string ("2 hours ago", "in 3 days")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short relative time string ("2h ago", "in 3d")
    var shortRelativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Component extraction
    var year: Int { Calendar.current.component(.year, from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
    var hour: Int { Calendar.current.component(.hour, from: self) }
    var weekday: Int { Calendar.current.component(.weekday, from: self) }

    var isWeekend: Bool { Calendar.current.isDateInWeekend(self) }
    var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(self) }
    var isInPast: Bool { self < Date() }
    var isInFuture: Bool { self > Date() }

    /// Days between two dates
    func days(until other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: self, to: other).day ?? 0
    }

    /// Age calculation
    var ageInYears: Int {
        Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0
    }
}
```

### Sequence & Collection Extensions (Additional)

```swift
// MARK: - Sorting by KeyPath

extension Sequence {
    /// Sort by a Comparable key path
    func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>, ascending: Bool = true) -> [Element] {
        sorted { a, b in
            ascending ? a[keyPath: keyPath] < b[keyPath: keyPath]
                      : a[keyPath: keyPath] > b[keyPath: keyPath]
        }
    }
}

// MARK: - Grouping

extension Sequence {
    /// Groups elements by a key
    func grouped<Key: Hashable>(by keyPath: (Element) -> Key) -> [Key: [Element]] {
        Dictionary(grouping: self, by: keyPath)
    }
}

// MARK: - Sum

extension Sequence where Element: Numeric {
    var sum: Element { reduce(0, +) }
}

extension Sequence {
    /// Sum values at a key path
    func sum<T: Numeric>(of keyPath: KeyPath<Element, T>) -> T {
        reduce(T.zero) { $0 + $1[keyPath: keyPath] }
    }
}

// MARK: - Non-Empty

extension Array {
    /// Returns nil if empty, otherwise self
    var nonEmpty: Self? { isEmpty ? nil : self }
}
```

### Optional Extensions (Additional)

```swift
extension Optional {
    /// Unwrap or throw an error
    func unwrapOrThrow(_ error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}

extension Optional where Wrapped: Collection {
    /// True if nil or empty
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
```

### Animation Extensions

```swift
extension Animation {
    /// Gentle ease-in-out (0.25s)
    static let gentle: Animation = .easeInOut(duration: 0.25)

    /// Standard transition (0.35s)
    static let standard: Animation = .easeInOut(duration: 0.35)

    /// Quick interactive spring
    static let quickSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    /// Bouncy spring for playful interactions
    static let bouncySpring: Animation = .spring(response: 0.5, dampingFraction: 0.5)

    /// Smooth spring with no bounce (Material-like)
    static let smoothSpring: Animation = .spring(response: 0.4, dampingFraction: 1.0)

    /// Staggered delay for list animations
    func staggered(index: Int, delayPerItem: Double = 0.05) -> Animation {
        self.delay(Double(index) * delayPerItem)
    }
}
```

### UIImage Extensions

```swift
extension UIImage {
    /// Resize maintaining aspect ratio
    func resized(toWidth width: CGFloat) -> UIImage {
        let scale = width / size.width
        let newHeight = size.height * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: newHeight))
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: CGSize(width: width, height: newHeight))) }
    }

    /// Compress to target file size
    func compressed(maxKB: Int = 500) -> Data? {
        var compression: CGFloat = 1.0
        var data = jpegData(compressionQuality: compression)
        while let d = data, d.count > maxKB * 1024, compression > 0.1 {
            compression -= 0.1
            data = jpegData(compressionQuality: compression)
        }
        return data
    }

    /// Circular crop
    var circularCropped: UIImage {
        let side = min(size.width, size.height)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: CGSize(width: side, height: side))
            UIBezierPath(ovalIn: rect).addClip()
            draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width, height: size.height
            ))
        }
    }

    /// Fix EXIF orientation
    var orientationFixed: UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
```

### View Extensions (Additional)

```swift
// MARK: - Read Size

extension View {
    /// Reads the view's size and calls the closure when it changes
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Fill Space Helpers

extension View {
    /// Expands to fill available width
    func fillWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    /// Expands to fill available height
    func fillHeight(alignment: Alignment = .center) -> some View {
        frame(maxHeight: .infinity, alignment: alignment)
    }

    /// Expands to fill all available space
    func fillSpace(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Haptic Feedback

extension View {
    /// Triggers haptic feedback on tap
    func onTapWithHaptic(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium,
        action: @escaping () -> Void
    ) -> some View {
        onTapGesture {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            action()
        }
    }
}

// MARK: - Debug Border

extension View {
    /// Adds a colored border for layout debugging (strips in release builds)
    func debugBorder(_ color: Color = .red) -> some View {
        #if DEBUG
        border(color)
        #else
        self
        #endif
    }
}

// MARK: - Hidden with Condition

extension View {
    /// Hides or shows the view based on a condition
    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden { self.hidden() }
        else { self }
    }
}

// MARK: - Reverse Mask

extension View {
    /// Masks by cutting out the shape (opposite of standard mask)
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            Rectangle()
                .overlay(alignment: .center) { mask().blendMode(.destinationOut) }
        )
    }
}
```

### Notification.Name Pattern

```swift
extension Notification.Name {
    static let userDidLogin = Notification.Name("app.userDidLogin")
    static let userDidLogout = Notification.Name("app.userDidLogout")
    static let deepLinkReceived = Notification.Name("app.deepLinkReceived")
    static let refreshRequired = Notification.Name("app.refreshRequired")
}
```

### EnvironmentValues Custom Key Pattern

```swift
// Step 1: Define the key
private struct ThemeOverrideKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

// Step 2: Extend EnvironmentValues
extension EnvironmentValues {
    var themeOverride: ColorScheme? {
        get { self[ThemeOverrideKey.self] }
        set { self[ThemeOverrideKey.self] = newValue }
    }
}

// Step 3: Convenience modifier
extension View {
    func themeOverride(_ theme: ColorScheme?) -> some View {
        environment(\.themeOverride, theme)
    }
}
```

---

## Appendix: Quick Reference Checklist

Use this when creating a new feature:

- [ ] Create `[Name]Feature.swift` with `@Reducer` struct
- [ ] Add `@ObservableState` struct `State: Equatable`
- [ ] Add `Action` enum with `ViewAction`, `BindableAction` (if needed) — **no `Equatable`**
- [ ] Organize actions: `alert`, `binding`, `delegate`, `internal`, `view` (alphabetical)
- [ ] Add `@CasePathable` and `Sendable` to all nested action enums
- [ ] Declare `@Dependency` properties inside the struct
- [ ] Build reducer body: BindingReducer -> Scopes -> Reduce -> Handlers -> Presentations
- [ ] Create `ReduceChild` handlers for each action category
- [ ] Create `[Name]View.swift` with `@ViewAction(for:)` macro
- [ ] Use `@Bindable var store` in the view
- [ ] Delegate body to private computed properties
- [ ] Scope store at point of use for child views
- [ ] Write tests with Apple Testing framework (`@Suite`, `@Test`, `#expect`)
- [ ] Use `.dependencies {}` test trait for shared test dependencies
- [ ] Use key path syntax for `receive`: `store.receive(\.internal.response.success)`
- [ ] Alphabetize imports, actions, handlers, and properties

---

*Last updated: February 2026*
