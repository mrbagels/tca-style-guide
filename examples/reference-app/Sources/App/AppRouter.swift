/// # App Router
/// @topic navigation
///
/// Top-level navigation coordinator. Manages a `TabView` with two tabs:
/// Items (with its own `NavigationStack` via `ItemsRouter`) and Settings
/// (single screen). Owns `AppDelegateFeature` as a child for lifecycle
/// coordination and deep link handling.
///
/// ## Key Rules
/// - One AppRouter per app — single entry point from `App.body`
/// - Each tab is a scoped child (router or feature)
/// - `AppDelegateFeature` is scoped as a child — lifecycle flows through TCA
/// - Deep links: read `state.appDelegate.pendingDeepLink`, act, then clear
/// - Cross-tab coordination via `Internal` actions
/// - `.ifLet` goes LAST in the body

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct AppRouter {

    // MARK: - Tab Definition

    /// Tab identity for `TabView(selection:)` binding.
    public enum Tab: Hashable, Sendable {
        case items
        case settings
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// App delegate lifecycle state — scoped as a child
        var appDelegate = AppDelegateFeature.State()
        /// Items tab router
        var itemsRouter = ItemsRouter.State()
        /// Currently selected tab
        var selectedTab: Tab = .items
        /// Settings feature (single screen, no router needed)
        var settings = SettingsFeature.State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        case appDelegate(AppDelegateFeature.Action)
        case binding(BindingAction<State>)
        case `internal`(Internal)
        case itemsRouter(ItemsRouter.Action)
        case settings(SettingsFeature.Action)
        case view(View)

        @CasePathable
        public enum Internal: Sendable {
            case handleDeepLink(AppDelegateFeature.DeepLink)
        }

        @CasePathable
        public enum View: Sendable {
            case onAppear
        }
    }

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.appDelegate, action: \.appDelegate) {
            AppDelegateFeature()
        }

        Scope(state: \.itemsRouter, action: \.itemsRouter) {
            ItemsRouter()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            default:
                return .none
            }
        }

        handleChildDelegation
        handleInternalActions
        handleViewActions
    }

    // MARK: - Child Delegation

    /// Coordinates delegate actions from children.
    /// Uses `Reduce` because it matches across multiple child types.
    private var handleChildDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // App delegate lifecycle — check for pending deep links
            case .appDelegate(.didBecomeActive):
                if let deepLink = state.appDelegate.pendingDeepLink {
                    state.appDelegate.pendingDeepLink = nil
                    return .send(.internal(.handleDeepLink(deepLink)))
                }
                return .none

            case .appDelegate(.openURL):
                if let deepLink = state.appDelegate.pendingDeepLink {
                    state.appDelegate.pendingDeepLink = nil
                    return .send(.internal(.handleDeepLink(deepLink)))
                }
                return .none

            // Items tab delegates
            case .itemsRouter(.delegate(.itemCreated)):
                /// Could trigger analytics, badge update, etc.
                return .none

            // Settings delegates
            case .settings(.delegate(.sortOrderChanged)):
                /// Could propagate sort preference to items list
                return .none

            default:
                return .none
            }
        }
    }

    // MARK: - Internal Handler

    private var handleInternalActions: ReduceChild<State, Action, Action.Internal> {
        ReduceChild(\.internal) { state, action in
            switch action {
            case .handleDeepLink(let link):
                switch link {
                case .item(let id):
                    state.selectedTab = .items
                    state.itemsRouter.path.append(
                        .detail(ItemDetailFeature.State(item: Item(
                            id: id,
                            title: "Loading...",
                            notes: ""
                        )))
                    )

                case .settings:
                    state.selectedTab = .settings
                }
                return .none
            }
        }
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .onAppear:
                return .none
            }
        }
    }
}
