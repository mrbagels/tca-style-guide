/// # App Delegate Feature
/// @topic navigation
///
/// TCA reducer that owns all app lifecycle state. UIKit lifecycle callbacks
/// (via `AppDelegate`) are translated into TCA actions here. This keeps
/// lifecycle concerns testable and composable — the `AppRouter` owns this
/// as a child via `Scope` and can react to lifecycle changes.
///
/// Simplified for the reference app: lifecycle events + deep link storage.
/// A production app would add push notification handling, background tasks,
/// and analytics initialization (see Embrace project for full example).
///
/// ## Key Rules
/// - All UIKit lifecycle callbacks become TCA actions
/// - Deep links are stored in state, consumed by the parent router
/// - No side effects in lifecycle handlers — keep them pure state mutations
/// - Parent (AppRouter) reads `pendingDeepLink` and clears it after handling

import ComposableArchitecture
import Foundation

// MARK: - Reducer

@Reducer
public struct AppDelegateFeature {

    // MARK: - Models

    /// Tracks the current application lifecycle phase.
    public enum AppLifecycleState: Sendable, Equatable {
        case active
        case background
        case inactive
        case launched
    }

    /// Typed deep link destinations parsed from incoming URLs.
    public enum DeepLink: Sendable, Equatable {
        case item(UUID)
        case settings

        /// Parses a URL into a typed deep link.
        /// Expected format: `referenceapp://items/{uuid}` or `referenceapp://settings`
        public static func from(url: URL) -> DeepLink? {
            guard url.scheme == "referenceapp" else { return nil }

            switch url.host {
            case "items":
                guard
                    let idString = url.pathComponents.dropFirst().first,
                    let id = UUID(uuidString: idString)
                else { return nil }
                return .item(id)

            case "settings":
                return .settings

            default:
                return nil
            }
        }
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Current lifecycle phase
        var lifecycleState: AppLifecycleState = .launched

        /// Deep link waiting to be consumed by the parent router.
        /// The parent reads this, acts on it, then sets it to `nil`.
        var pendingDeepLink: DeepLink?

        public init() {}
    }

    // MARK: - Action

    public enum Action: Sendable {
        case didBecomeActive
        case didEnterBackground
        case didFinishLaunching
        case openURL(URL)
        case willEnterForeground
        case willResignActive
        case willTerminate
    }

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .didBecomeActive:
                state.lifecycleState = .active
                return .none

            case .didEnterBackground:
                state.lifecycleState = .background
                return .none

            case .didFinishLaunching:
                state.lifecycleState = .active
                return .none

            case .openURL(let url):
                state.pendingDeepLink = DeepLink.from(url: url)
                return .none

            case .willEnterForeground:
                state.lifecycleState = .inactive
                return .none

            case .willResignActive:
                state.lifecycleState = .inactive
                return .none

            case .willTerminate:
                return .none
            }
        }
    }
}
