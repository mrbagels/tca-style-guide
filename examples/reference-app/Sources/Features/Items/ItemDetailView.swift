/// # Item Detail View
/// @topic view
///
/// Detail screen for displaying a single item. Demonstrates `.sheet(item:)`
/// with scoped store for presenting the editor, toolbar actions for edit/delete,
/// and conditional UI based on loading state.
///
/// ## Key Rules
/// - `@ViewAction(for:)` macro — never `store.send()` directly
/// - Scope stores at point of use in `.sheet(item:)`
/// - Extract sections as `private var` computed properties

import ComposableArchitecture
import SwiftUI

// MARK: - View

@ViewAction(for: ItemDetailFeature.self)
public struct ItemDetailView: View {
    @Bindable public var store: StoreOf<ItemDetailFeature>

    public init(store: StoreOf<ItemDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        List {
            titleSection
            detailsSection
            deleteSection
        }
        .navigationTitle(store.item.title)
        .toolbar { toolbarContent }
        .alert($store.scope(state: \.alert, action: \.alert))
        .sheet(
            item: $store.scope(
                state: \.destination?.edit,
                action: \.destination.edit
            )
        ) { editorStore in
            ItemEditorView(store: editorStore)
        }
        .disabled(store.isDeleting)
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section("Title") {
            Text(store.item.title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            if let price = store.item.price {
                LabeledContent("Price") {
                    Text(price, format: .currency(code: "USD"))
                }
            }

            if !store.item.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.item.notes)
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                send(.deleteButtonTapped)
            } label: {
                HStack {
                    Spacer()
                    if store.isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete Item")
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Edit") { send(.editButtonTapped) }
        }
    }
}
