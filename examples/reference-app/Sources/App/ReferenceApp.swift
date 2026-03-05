/// # Reference App Entry Point
/// @topic navigation
///
/// The `@main` entry point for the TCA reference app. Creates the root store,
/// injects the scoped `AppDelegateFeature` store into the `AppDelegate`, and
/// guards against running reducers during unit tests.
///
/// ## Key Rules
/// - `@UIApplicationDelegateAdaptor` bridges UIKit lifecycle into TCA
/// - Root store created once, lives for the app's lifetime
/// - Scoped `AppDelegateFeature` store injected into delegate in `init()`
/// - `_XCTIsTesting` guard prevents side effects during test execution

import ComposableArchitecture
import SwiftUI

// MARK: - App

@main
struct ReferenceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    /// Root store — created once, lives for the app's lifetime
    let store: StoreOf<AppRouter>

    init() {
        let store = Store(initialState: AppRouter.State()) {
            AppRouter()
        }
        self.store = store

        /// Inject the scoped AppDelegateFeature store into the delegate.
        /// This connects UIKit lifecycle callbacks → TCA actions.
        delegate.store = store.scope(
            state: \.appDelegate,
            action: \.appDelegate
        )
    }

    var body: some Scene {
        WindowGroup {
            /// Guard: prevent app reducer from running during unit tests
            if !_XCTIsTesting {
                AppRouterView(store: store)
            }
        }
    }
}
