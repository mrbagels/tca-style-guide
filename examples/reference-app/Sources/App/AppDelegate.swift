/// # App Delegate
/// @topic navigation
///
/// UIKit `UIApplicationDelegate` that bridges lifecycle events into TCA.
/// Receives a scoped `StoreOf<AppDelegateFeature>` from the app entry point
/// and translates every UIKit callback into a TCA action.
///
/// This class does NO logic — it only sends actions. All behavior lives in
/// `AppDelegateFeature` where it's testable.
///
/// ## Key Rules
/// - `store` is injected by the `@main` App struct after store creation
/// - Every lifecycle method calls `store.send(...)` — nothing else
/// - No business logic in this class — it's a pure UIKit → TCA bridge
/// - `SceneDelegate` is configured via `configurationForConnecting`

import ComposableArchitecture
import UIKit

// MARK: - App Delegate

public final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Scoped store injected by the App entry point.
    /// Set immediately after the root store is created.
    public var store: StoreOf<AppDelegateFeature>?

    // MARK: - Lifecycle

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        store?.send(.didFinishLaunching)
        return true
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        store?.send(.willEnterForeground)
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        store?.send(.didBecomeActive)
    }

    public func applicationWillResignActive(_ application: UIApplication) {
        store?.send(.willResignActive)
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        store?.send(.didEnterBackground)
    }

    public func applicationWillTerminate(_ application: UIApplication) {
        store?.send(.willTerminate)
    }

    // MARK: - Deep Links

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        store?.send(.openURL(url))
        return true
    }

    // MARK: - Scene Configuration

    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}
