/// # App Router Tests
/// @topic testing
///
/// Tests for `AppRouter` demonstrating:
/// - Deep link handling via AppDelegateFeature
/// - Tab switching
/// - Lifecycle coordination between delegate and router
///
/// ## Key Rules
/// - `TestStore` with `exhaustivity = .off` when testing coordination
///   paths where intermediate child actions aren't relevant
/// - Deep link tests verify both tab selection and path mutation
/// - Lifecycle tests verify delegate → router coordination

import ComposableArchitecture
import Testing

@Suite("AppRouter Tests")
struct AppRouterTests {

    // MARK: - Deep Links

    @Test("Item deep link switches to items tab and pushes detail")
    func itemDeepLinkSwitchesTab() async {
        let itemID = Item.preview.id

        let store = TestStore(initialState: AppRouter.State()) {
            AppRouter()
        }

        /// Simulate deep link arriving via AppDelegate
        await store.send(.appDelegate(.openURL(
            URL(string: "referenceapp://items/\(itemID.uuidString)")!
        ))) {
            $0.appDelegate.pendingDeepLink = .item(itemID)
        }

        /// Router consumes the deep link
        await store.receive(\.internal.handleDeepLink) {
            $0.selectedTab = .items
            $0.itemsRouter.path[id: 0] = .detail(
                ItemDetailFeature.State(item: Item(
                    id: itemID,
                    title: "Loading...",
                    notes: ""
                ))
            )
        }
    }

    @Test("Settings deep link switches to settings tab")
    func settingsDeepLinkSwitchesTab() async {
        let store = TestStore(initialState: AppRouter.State()) {
            AppRouter()
        }

        await store.send(.appDelegate(.openURL(
            URL(string: "referenceapp://settings")!
        ))) {
            $0.appDelegate.pendingDeepLink = .settings
        }

        await store.receive(\.internal.handleDeepLink) {
            $0.selectedTab = .settings
        }
    }

    @Test("Invalid URL produces no deep link")
    func invalidURLNoDeepLink() async {
        let store = TestStore(initialState: AppRouter.State()) {
            AppRouter()
        }

        await store.send(.appDelegate(.openURL(
            URL(string: "https://example.com")!
        )))
    }

    // MARK: - Lifecycle

    @Test("Did finish launching sets lifecycle state")
    func didFinishLaunchingSetsState() async {
        let store = TestStore(initialState: AppRouter.State()) {
            AppRouter()
        }

        await store.send(.appDelegate(.didFinishLaunching)) {
            $0.appDelegate.lifecycleState = .active
        }
    }

    @Test("Did become active processes pending deep link")
    func didBecomeActiveProcessesDeepLink() async {
        var initialState = AppRouter.State()
        initialState.appDelegate.pendingDeepLink = .settings

        let store = TestStore(initialState: initialState) {
            AppRouter()
        }

        await store.send(.appDelegate(.didBecomeActive)) {
            $0.appDelegate.lifecycleState = .active
            $0.appDelegate.pendingDeepLink = nil
        }

        await store.receive(\.internal.handleDeepLink) {
            $0.selectedTab = .settings
        }
    }

    // MARK: - Tab Switching

    @Test("Tab selection via binding updates state")
    func tabSelectionUpdatesState() async {
        let store = TestStore(initialState: AppRouter.State()) {
            AppRouter()
        }

        await store.send(.binding(.set(\.selectedTab, .settings))) {
            $0.selectedTab = .settings
        }
    }
}
