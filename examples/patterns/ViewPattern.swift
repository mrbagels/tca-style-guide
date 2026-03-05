/// # View Pattern
/// @topic view
///
/// TCA views follow strict conventions for store access, body structure,
/// and subview extraction.
///
/// ## Key Rules
/// - Always use `@ViewAction(for:)` macro — never `store.send()` directly
/// - Use `@Bindable var store` for binding support
/// - Keep body minimal — delegate to `private var` computed properties
/// - Scope stores at point of use, never in parent
/// - Never use `Binding(get:set:)` — it bypasses TCA's state management
/// - Avoid high-frequency actions (scroll offsets, drag gestures) — debounce or use local `@State`

import ComposableArchitecture
import SwiftUI

// MARK: - Standard View

/// `@ViewAction` generates a `send(_:)` function that dispatches `.view(...)` actions.
/// This replaces `store.send(.view(.onAppear))` with just `send(.onAppear)`.
@ViewAction(for: ProfileFeature.self)
public struct ProfileView: View {

    /// `@Bindable` enables `$store.propertyName` binding syntax.
    /// This works because Action conforms to `BindableAction`.
    @Bindable public var store: StoreOf<ProfileFeature>

    public init(store: StoreOf<ProfileFeature>) {
        self.store = store
    }

    /// Body is kept minimal — each section is a private computed property.
    /// Modifiers like `.task`, `.alert`, `.sheet` attach here.
    public var body: some View {
        NavigationStack {
            ScrollView {
                headerSection
                contentSection
                actionButtons
            }
            .navigationTitle("Profile")
            .toolbar { toolbarContent }
            /// Use `.task` instead of `.onAppear` for async lifecycle
            .task { send(.onAppear) }
            /// Alert binding uses scoped store
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    // MARK: - Sections

    /// Extract sections as `private var` when they exceed ~10 lines
    /// or represent a logically distinct UI block.
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(store.displayName)
                .font(.title)
            Text(store.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Use `@ViewBuilder` when the property has conditional logic.
    @ViewBuilder
    private var contentSection: some View {
        if store.isLoading {
            ProgressView()
        } else {
            List(store.items) { item in
                ItemRow(item: item)
            }
        }
    }

    private var actionButtons: some View {
        Button("Save") {
            send(.saveButtonTapped)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    /// Toolbar content uses `@ToolbarContentBuilder`.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { send(.doneButtonTapped) }
        }
    }
}

// MARK: - Focus State Management

/// Focus state is managed through TCA bindings, not raw SwiftUI `@FocusState`.
/// The feature defines a `Field` enum, and the view binds it.
@ViewAction(for: LoginFeature.self)
struct LoginView: View {
    @Bindable var store: StoreOf<LoginFeature>
    /// Local `@FocusState` mirrors TCA's `store.focus` property
    @FocusState var focus: LoginFeature.Field?

    var body: some View {
        Form {
            TextField("Email", text: $store.email)
                .focused($focus, equals: .email)
            SecureField("Password", text: $store.password)
                .focused($focus, equals: .password)
        }
        /// `.bind` syncs TCA state ↔ SwiftUI FocusState bidirectionally
        .bind($store.focus, to: $focus)
    }
}

// MARK: - Store Scoping Examples

/**
 Store scoping should ALWAYS happen at the point of use, not ahead of time.

 ```swift
 // CORRECT — scope where it's consumed
 .sheet(item: $store.scope(state: \.editProfile, action: \.editProfile)) { editStore in
     EditProfileView(store: editStore)
 }

 // CORRECT — inline child scoping
 ChildFeatureView(
     store: store.scope(state: \.childFeature, action: \.childFeature)
 )

 // INCORRECT — never pre-scope in a computed property
 var childStore: StoreOf<ChildFeature> {
     store.scope(state: \.childFeature, action: \.childFeature) // Don't do this
 }
 ```
 */
private struct _ScopingDocumentation {}
