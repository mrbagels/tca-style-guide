/// # App Router Pattern
/// @topic navigation
///
/// The AppRouter is the top-level navigation coordinator for the entire application.
/// It manages a `TabView` where each tab owns its own navigation stack via a
/// dedicated tab router. Cross-tab coordination (deep links, global modals,
/// authentication gates) is handled here — never inside individual features.
///
/// ## Key Rules
/// - One AppRouter per app — it is the single entry point from `App.body`
/// - Each tab is a scoped child router with its own `StackState<Path.State>`
/// - Cross-tab navigation is coordinated via `Internal` actions, never by reaching into child state
/// - Global modals (login, paywall, onboarding) use `@Presents var destination`
/// - Deep link handling converts a URL into an `Internal` action that mutates the correct tab + path
/// - The `selectedTab` property drives `TabView(selection:)` via `BindableAction`
/// - Tab routers delegate upward — AppRouter decides whether to switch tabs or present modals

import ComposableArchitecture
import SwiftUI

// MARK: - App Router Reducer

@Reducer
public struct AppRouter {

    // MARK: - Tab Definition

    /// Enum for tab identity. Used as the `TabView(selection:)` binding value.
    /// Alphabetized. Conforms to `Hashable` for SwiftUI `tag()`.
    public enum Tab: Hashable, Sendable {
        case home
        case profile
        case settings
    }

    // MARK: - Destination (Global Modals)

    /// Global modals that can appear from any tab — login walls, paywalls,
    /// onboarding flows, etc. These are distinct from tab-level modals.
    @Reducer
    public enum Destination {
        case onboarding(OnboardingFeature)
        case paywall(PaywallFeature)
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Global modal destination — appears over the entire tab bar
        @Presents var destination: Destination.State?

        /// Each tab gets its own router state, scoped independently.
        /// Alphabetized to match the `Tab` enum.
        var homeRouter = HomeRouter.State()
        var profileRouter = ProfileRouter.State()

        /// The currently selected tab — bound to `TabView(selection:)`
        var selectedTab: Tab = .home

        /// Settings doesn't need a router if it's a single screen
        var settings = SettingsFeature.State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        /// Two-way binding for `selectedTab` and any other bound state
        case binding(BindingAction<State>)
        /// Global modal actions
        case destination(PresentationAction<Destination.Action>)
        /// Scoped tab router actions — alphabetized
        case homeRouter(HomeRouter.Action)
        /// Internal coordination — deep links, cross-tab navigation
        case `internal`(Internal)
        case profileRouter(ProfileRouter.Action)
        /// Settings feature actions (no router needed for single screen)
        case settings(SettingsFeature.Action)
        /// Direct user interactions from the AppRouter view itself
        case view(View)

        @CasePathable
        public enum Internal: Sendable {
            /// Deep link handling — the URL has been parsed into a typed destination
            case deepLinkReceived(DeepLink)
            /// Cross-tab coordination
            case navigateToProfile
            case showPaywall
        }

        @CasePathable
        public enum View: Sendable {
            case onAppear
        }
    }

    // MARK: - Dependencies

    @Dependency(\.authClient) var authClient

    public init() {}

    // MARK: - Body

    /// Composition order for the AppRouter:
    /// 1. BindingReducer — processes tab selection changes
    /// 2. Scope each tab router — they reduce their own state
    /// 3. Scope standalone features (settings)
    /// 4. Reduce — cross-cutting passthrough
    /// 5. Handlers — coordination logic
    /// 6. .ifLet — global destination presentation (ALWAYS LAST)
    public var body: some ReducerOf<Self> {
        BindingReducer()

        /// Each tab router is scoped to its own state/action slice.
        /// They handle their own navigation internally and only
        /// communicate upward via `.delegate` actions.
        Scope(state: \.homeRouter, action: \.homeRouter) {
            HomeRouter()
        }

        Scope(state: \.profileRouter, action: \.profileRouter) {
            ProfileRouter()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .binding, .destination:
                return .none
            default:
                return .none
            }
        }

        handleInternalActions
        handleViewActions
        handleChildDelegation

        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .onAppear:
                /// Check if onboarding is needed on first launch
                return .run { [authClient] send in
                    let needsOnboarding = await authClient.needsOnboarding()
                    if needsOnboarding {
                        await send(.internal(.deepLinkReceived(.onboarding)))
                    }
                }
            }
        }
    }

    // MARK: - Internal Handler (Coordination)

    /// This is where cross-tab navigation and deep linking lives.
    /// The AppRouter is the ONLY place that knows about all tabs.
    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .deepLinkReceived(let link):
                /// Deep link handling: parse the link type and mutate
                /// the correct tab's state directly. This is state mutation
                /// in the reducer — not action ping-pong.
                switch link {
                case .item(let id):
                    state.selectedTab = .home
                    state.homeRouter.path.append(
                        .detail(ItemDetailFeature.State(itemID: id))
                    )
                case .profile:
                    state.selectedTab = .profile
                case .onboarding:
                    state.destination = .onboarding(OnboardingFeature.State())
                }
                return .none

            case .navigateToProfile:
                /// Cross-tab navigation — switch tab and optionally push
                state.selectedTab = .profile
                return .none

            case .showPaywall:
                state.destination = .paywall(PaywallFeature.State())
                return .none
            }
        }
    }

    // MARK: - Child Delegation

    /// Coordinates delegate actions from tab routers.
    /// Uses `Reduce` (not `ReduceChild`) because it needs to match
    /// across multiple child feature types — this is the ONE justified case.
    private var handleChildDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            /// Home tab delegates
            case .homeRouter(.delegate(.profileRequested)):
                state.selectedTab = .profile
                return .none

            case .homeRouter(.delegate(.premiumRequired)):
                return .send(.internal(.showPaywall))

            /// Profile tab delegates
            case .profileRouter(.delegate(.loggedOut)):
                /// Reset all tab state on logout
                state.homeRouter = HomeRouter.State()
                state.profileRouter = ProfileRouter.State()
                state.settings = SettingsFeature.State()
                state.selectedTab = .home
                return .none

            /// Settings delegates
            case .settings(.delegate(.accountDeleted)):
                state.homeRouter = HomeRouter.State()
                state.profileRouter = ProfileRouter.State()
                state.settings = SettingsFeature.State()
                state.selectedTab = .home
                return .none

            /// Global modal delegates
            case .destination(.presented(.onboarding(.delegate(.completed)))):
                state.destination = nil
                return .none

            case .destination(.presented(.paywall(.delegate(.purchased)))):
                state.destination = nil
                return .none

            default:
                return .none
            }
        }
    }
}

// MARK: - Deep Link Model

/// Typed deep link destinations. Parse URLs into these
/// before sending to the router.
public enum DeepLink: Sendable, Equatable {
    case item(Item.ID)
    case onboarding
    case profile
}

// MARK: - App Router View

/// The AppRouter view renders a `TabView` with each tab scoped
/// to its own router/feature store. Global modals overlay everything.
@ViewAction(for: AppRouter.self)
public struct AppRouterView: View {
    @Bindable public var store: StoreOf<AppRouter>

    public init(store: StoreOf<AppRouter>) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: $store.selectedTab) {
            homeTab
            profileTab
            settingsTab
        }
        /// Global modals — these overlay the entire tab bar
        .fullScreenCover(
            item: $store.scope(
                state: \.destination?.onboarding,
                action: \.destination.onboarding
            )
        ) { onboardingStore in
            OnboardingView(store: onboardingStore)
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.paywall,
                action: \.destination.paywall
            )
        ) { paywallStore in
            PaywallView(store: paywallStore)
        }
        .task { send(.onAppear) }
    }

    // MARK: - Tab Views

    /// Each tab scopes its store at point of use.
    /// The tab's NavigationStack lives inside the tab router view.
    private var homeTab: some View {
        HomeRouterView(
            store: store.scope(state: \.homeRouter, action: \.homeRouter)
        )
        .tabItem { Label("Home", systemImage: "house") }
        .tag(AppRouter.Tab.home)
    }

    private var profileTab: some View {
        ProfileRouterView(
            store: store.scope(state: \.profileRouter, action: \.profileRouter)
        )
        .tabItem { Label("Profile", systemImage: "person") }
        .tag(AppRouter.Tab.profile)
    }

    /// Settings is a single feature, not a router — no NavigationStack needed
    private var settingsTab: some View {
        NavigationStack {
            SettingsView(
                store: store.scope(state: \.settings, action: \.settings)
            )
        }
        .tabItem { Label("Settings", systemImage: "gear") }
        .tag(AppRouter.Tab.settings)
    }
}

// MARK: - App Entry Point

/**
 The `App` struct creates the root store and guards against
 running reducers during unit tests.

 ```swift
 @main
 struct MyApp: App {
     /// Root store — created once, lives for the app's lifetime
     let store = Store(initialState: AppRouter.State()) {
         AppRouter()
     }

     var body: some Scene {
         WindowGroup {
             /// Guard: prevent app reducer from running during tests
             if !_XCTIsTesting {
                 AppRouterView(store: store)
             }
         }
     }
 }
 ```

 **Rule (G15):** Always guard `_XCTIsTesting` in the App body.
 Without this, the app's full reducer runs during test execution,
 causing side effects and slow test suites.
 */
private struct _AppEntryDocumentation {}
