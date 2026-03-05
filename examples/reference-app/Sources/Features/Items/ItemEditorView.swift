/// # Item Editor View
/// @topic view
///
/// Form view for creating/editing items. Demonstrates `@FocusState` with
/// `.bind()` for TCA-managed focus, inline validation error display,
/// `@Bindable` for form field bindings, and toolbar with save/cancel actions.
///
/// ## Key Rules
/// - `@FocusState` mirrors TCA's `store.focus` via `.bind($store.focus, to: $focus)`
/// - Inline validation errors rendered per-field from `store.validationErrors`
/// - Form disabled during save (`store.isSaving`)
/// - Extract form sections as `private var` computed properties

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: ItemEditorFeature.self)
public struct ItemEditorView: View {
    @Bindable public var store: StoreOf<ItemEditorFeature>

    /// Local `@FocusState` mirrors TCA's `store.focus` property
    @FocusState var focus: ItemEditorFeature.Field?

    public init(store: StoreOf<ItemEditorFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                titleSection
                detailsSection
            }
            .navigationTitle(store.originalItem == nil ? "New Item" : "Edit Item")
            .toolbar { toolbarContent }
            .alert($store.scope(state: \.alert, action: \.alert))
            .bind($store.focus, to: $focus)
            .disabled(store.isSaving)
            .task { send(.onAppear) }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $store.title)
                .focused($focus, equals: .title)

            if let error = store.validationErrors[.title] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Title")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Price", value: $store.price, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .focused($focus, equals: .price)

            if let error = store.validationErrors[.price] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Notes", text: $store.notes, axis: .vertical)
                .lineLimit(3...6)
                .focused($focus, equals: .notes)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { send(.cancelButtonTapped) }
        }
        ToolbarItem(placement: .confirmationAction) {
            if store.isSaving {
                ProgressView()
            } else {
                Button("Save") { send(.saveButtonTapped) }
                    .disabled(!store.validationErrors.isEmpty)
            }
        }
    }
}
