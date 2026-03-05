/// # Settings View
/// @topic view
///
/// Demonstrates a form-based settings screen with `@Bindable` store bindings
/// for Toggle, Picker, and TextField. Uses `@ViewAction` for explicit
/// user interactions (reset) and `$store.property` for continuous bindings.
///
/// ## Key Rules
/// - `@ViewAction(for:)` macro generates `send(_:)` function
/// - `@Bindable var store` enables `$store.property` binding syntax
/// - Extract form sections as `private var` computed properties
/// - Scope stores at point of use, never pre-scope

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: SettingsFeature.self)
public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            profileSection
            preferencesSection
            resetSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section("Profile") {
            TextField("Display Name", text: $store.displayName)
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Toggle("Notifications", isOn: $store.notificationsEnabled)

            Picker("Sort Order", selection: $store.sortOrder) {
                ForEach(SettingsFeature.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue.capitalized)
                        .tag(order)
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                send(.resetButtonTapped)
            } label: {
                HStack {
                    Spacer()
                    Text("Reset to Defaults")
                    Spacer()
                }
            }
        }
    }
}
