/// # Testing Pattern
/// @topic testing
///
/// TCA features are tested via `TestStore`, which provides exhaustive
/// assertion checking — every state change and received action must be
/// explicitly verified.
///
/// ## Key Rules
/// - Use `TestStore` for all reducer tests
/// - Override dependencies via `withDependencies` closure
/// - Use case key path syntax for `receive` (not `Equatable`)
/// - Test state changes exhaustively — `TestStore` fails on unexpected mutations
/// - Test delegate actions to verify parent communication contracts
/// - Use `$0.exhaustivity = .off` sparingly and only with a comment explaining why

import ComposableArchitecture
import Testing

// MARK: - Basic Feature Tests

@Suite("ProfileFeature Tests")
struct ProfileFeatureTests {

    /// Basic flow test: onAppear → loading → response → state updated
    @Test("Profile loads on appear")
    func profileLoadsOnAppear() async {
        let expectedProfile = Profile(id: "1", name: "Kyle")

        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            /// Override only the dependencies this test needs.
            /// Un-overridden calls fail via `unimplemented()` in testValue.
            $0.profileClient.fetch = { .success(expectedProfile) }
        }

        /// Send a view action and assert resulting state changes
        await store.send(.view(.onAppear)) {
            $0.isLoading = true
        }

        /// Receive the internal action triggered by the effect.
        /// Uses case key path syntax — no `Equatable` needed on Action.
        await store.receive(\.internal.profileResponse.success) {
            $0.displayName = "Kyle"
            $0.isLoading = false
        }
    }

    /// Error handling test: verify failure path sets correct state
    @Test("Profile handles fetch failure")
    func profileHandlesFetchFailure() async {
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.profileClient.fetch = { .failure(NSError(domain: "", code: -1)) }
        }

        await store.send(.view(.onAppear)) {
            $0.isLoading = true
        }

        await store.receive(\.internal.profileResponse.failure) {
            $0.isLoading = false
        }
    }

    /// Delegate test: verify the feature communicates correctly to parent
    @Test("Delete sends delegate action")
    func deleteSendsDelegateAction() async {
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        }

        /// Trigger alert
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

        /// Confirm deletion in alert → should emit delegate action
        await store.send(.alert(.presented(.confirmDeleteTapped)))

        /// Verify delegate action is received — this is the contract with parent
        await store.receive(\.delegate.profileDeleted)
    }
}

// MARK: - Testing with Clock

/**
 For time-based tests (debounce, timers), use TCA's `TestClock`:

 ```swift
 @Test("Search debounces input")
 func searchDebounces() async {
     let clock = TestClock()

     let store = TestStore(initialState: SearchFeature.State()) {
         SearchFeature()
     } withDependencies: {
         $0.continuousClock = clock
         $0.searchClient.search = { query in .success([]) }
     }

     await store.send(.view(.searchTextChanged("sw"))) {
         $0.searchText = "sw"
     }

     /// Advance clock by debounce duration
     await clock.advance(by: .milliseconds(300))

     await store.receive(\.internal.searchResponse.success) {
         $0.results = []
     }
 }
 ```
 */
private struct _ClockDocumentation {}

// MARK: - Testing Navigation

/**
 Router tests verify navigation state changes:

 ```swift
 @Test("Selecting item pushes detail")
 func selectingItemPushesDetail() async {
     let store = TestStore(initialState: ItemsRouter.State()) {
         ItemsRouter()
     }

     await store.send(.root(.delegate(.itemSelected("item-1")))) {
         $0.path.append(.detail(ItemDetailFeature.State(itemID: "item-1")))
     }
 }
 ```
 */
private struct _NavigationDocumentation {}
