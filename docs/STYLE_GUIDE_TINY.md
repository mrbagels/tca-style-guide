# TCA / SwiftUI / SQLiteData Architecture Spec (Slim)

## Global Philosophy

-   Consistency \> cleverness
-   Alphabetize everything
-   Exhaustive switch preferred
-   Composition \> monolith
-   Test by default
-   Parents observe child delegate only
-   Never mutate state in effects
-   Navigation state must pair with reducer operator
-   Never conform top-level Action to Equatable

## Feature Pattern

-   @Reducer struct XFeature
-   @ObservableState struct State: Equatable
-   enum Action: ViewAction (+ BindableAction only if needed)
-   Dependencies declared inside reducer
-   public init() {}

## Action Structure

Top-level (alphabetical): - alert(PresentationAction`<Alert>`{=html}) -
binding(BindingAction`<State>`{=html}) - child(ChildFeature.Action) -
delegate(Delegate) -
destination(PresentationAction\<Destination.Action\>) -
internal(Internal) - path(StackActionOf`<Path>`{=html}) - view(View)

Nested enums: - @CasePathable - Sendable - Alphabetical

Naming: - View = literal interaction (saveButtonTapped) - Internal =
business result (dataResponse) - Delegate = parent communication
(didComplete)

Rule: Parent observes child.delegate only.

## Reducer Composition Order

1.  BindingReducer()
2.  Scope(...)
3.  Reduce passthrough only
4.  handleXActions
5.  .ifLet / .forEach

## ReduceChild

-   Primary reducer splitting mechanism
-   One per action category
-   Never send child.view or child.internal

## View Rules

-   @ViewAction(for: Feature.self)
-   @Bindable var store
-   Body minimal
-   Extract \>10 lines
-   Subviews private
-   Scope store at point of use
-   NEVER use Binding(get:set:)
-   Avoid high-frequency actions

## Router

-   root
-   path (StackState)
-   destination (@Presents)
-   Scope root
-   .forEach path
-   .ifLet destination
-   Never construct navigation state in view layer

## State

-   @ObservableState
-   No willSet/didSet
-   @Shared uses reference semantics (use withLock)
-   @Presents optional child state

## Dependencies

-   @DependencyClient
-   Live in +Live file
-   TestDependencyKey required
-   Declare @Dependency inside reducer

## SQLiteData

-   @Table models (singular)
-   DB tables plural
-   Non-null columns require DEFAULT
-   Raw #sql migrations only
-   Never edit shipped migrations
-   Create-Copy-Drop-Rename for schema rewrites
-   withAnimation does NOT animate Fetch (use animation: param)

Sync: - Explicit tables opt-in - No compound PK - No unique indexes
except PK - No reserved iCloud names - Cannot share many-to-many tables

## Testing

-   Swift Testing (@Suite, @Test, #expect)
-   Override continuousClock
-   Negative UUIDs for tests
-   Positive UUIDs for previews
-   Guard !\_XCTIsTesting in App
-   store.exhaustivity = .off for partial assertions

## Critical Gotchas

G1 parent !child.view,!child.internal G2 missing BindingReducer breaks
bindings G3 missing .ifLet/.forEach prevents child reducer G4 never
mutate state in effect G5 cancel long-running effects G6 avoid action
ping-pong G7 @Shared reference semantics G8 avoid high-frequency actions
G9 cancelInFlight must be per-instance G10 Binding(get:set:) bypasses
TCA G11 willSet/didSet causes loops G12 no navigation construction in
view G13 withAnimation doesn't animate Fetch G14 override
continuousClock in tests G15 guard App during tests G16 capture specific
state values in effects
