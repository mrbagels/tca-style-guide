/// # App Router View
/// @topic view
///
/// Root view of the application. Renders a `TabView` with each tab scoped
/// to its own router or feature store. Demonstrates `TabView(selection:)`
/// with `$store.selectedTab` binding and store scoping at point of use.
///
/// ## Key Rules
/// - `TabView(selection:)` binds to router's `selectedTab` state
/// - Each tab scopes its store at point of use
/// - Tab routers own their own `NavigationStack`
/// - Single-screen tabs wrap in `NavigationStack` locally

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: AppRouter.self)
public struct AppRouterView: View {
    @Bindable public var store: StoreOf<AppRouter>

    public init(store: StoreOf<AppRouter>) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: $store.selectedTab) {
            itemsTab
            settingsTab
        }
        .task { send(.onAppear) }
    }

    // MARK: - Tabs

    /// Items tab — owns a full NavigationStack via ItemsRouterView
    private var itemsTab: some View {
        ItemsRouterView(
            store: store.scope(state: \.itemsRouter, action: \.itemsRouter)
        )
        .tabItem { Label("Items", systemImage: "list.bullet") }
        .tag(AppRouter.Tab.items)
    }

    /// Settings tab — single screen, wrapped in NavigationStack locally
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
