/// # Complete Feature Pattern
/// @topic architecture
///
/// A production-grade TCA feature demonstrating every pattern in realistic context:
/// form editing with validation, async API operations with cancellation, optimistic
/// updates with rollback on failure, confirmation alerts, child feature presentation,
/// delegate communication, and proper error recovery.
///
/// This goes beyond the basic `FeaturePattern.swift` template to show how the
/// patterns compose under real-world pressure.
///
/// ## Key Rules
/// - Capture specific state values in `.run` closures — never the full `state`
/// - Always provide cancellation IDs for cancellable effects
/// - Handle both `.success` and `.failure` of every `Result`
/// - Use optimistic updates: mutate state immediately, roll back on failure
/// - Validation logic lives in the reducer, never in the view
/// - Form state uses `BindableAction` for two-way bindings
/// - Child features communicate via `.delegate` only

import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Reducer

@Reducer
public struct ItemEditorFeature {

    // MARK: - Child Feature (Presented)

    /// Child features presented as sheets/modals use `@Reducer enum Destination`
    @Reducer
    public enum Destination {
        case categoryPicker(CategoryPickerFeature)
        case imagePicker(ImagePickerFeature)
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// Alert state — typed to the Alert action enum
        @Presents var alert: AlertState<Action.Alert>?

        /// Category selected from the picker child feature
        var category: Category?

        /// Modal destination — managed by `.ifLet(\.$destination)`
        @Presents var destination: Destination.State?

        /// Focus tracking for form fields — synced with SwiftUI via `.bind()`
        var focus: Field? = .title

        /// Image attachment (optional)
        var imageData: Data?

        /// Whether a save/delete operation is in flight
        var isSaving = false

        /// The item being edited — `nil` means creating a new item
        var itemID: Item.ID?

        /// Form field: item notes (multi-line)
        var notes = ""

        /// Snapshot of the item before editing — used for optimistic rollback
        var originalItem: Item?

        /// Form field: item price
        var price: Decimal?

        /// Form field: item title
        var title = ""

        /// Validation errors — computed per-field, displayed inline
        var validationErrors: [Field: String] = [:]

        public init() {}

        /// Convenience initializer for editing an existing item
        public init(item: Item) {
            self.category = item.category
            self.itemID = item.id
            self.notes = item.notes
            self.originalItem = item
            self.price = item.price
            self.title = item.title
        }
    }

    /// Focus field enum — mirrors form fields for `@FocusState` binding
    public enum Field: Hashable, Sendable {
        case notes
        case price
        case title
    }

    // MARK: - Action

    public enum Action: ViewAction, BindableAction {
        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        case `internal`(Internal)
        case view(View)

        @CasePathable
        public enum Alert: Sendable {
            case confirmDeleteTapped
            case discardChangesTapped
        }

        /// Delegate actions — the parent listens to these.
        /// Named with past tense to indicate something happened.
        @CasePathable
        public enum Delegate: Sendable {
            case itemDeleted(Item.ID)
            case itemSaved(Item)
        }

        @CasePathable
        public enum Internal: Sendable {
            case deleteResponse(Result<Void, Error>)
            case saveResponse(Result<Item, Error>)
            case validationCompleted
        }

        /// View actions — named after the literal user interaction
        @CasePathable
        public enum View: Sendable {
            case cancelButtonTapped
            case categoryFieldTapped
            case deleteButtonTapped
            case imagePickerButtonTapped
            case onAppear
            case saveButtonTapped
        }
    }

    // MARK: - Cancellation IDs

    /// Static cancellation IDs for long-running effects.
    /// Using an enum prevents typos and enables `.cancel(id:)`.
    private enum CancelID {
        case delete
        case save
    }

    // MARK: - Dependencies

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.itemClient) var itemClient
    @Dependency(\.uuid) var uuid

    public init() {}

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none

            /// On any binding change (text field edit), re-validate
            case .binding:
                return .send(.internal(.validationCompleted))

            default:
                return .none
            }
        }

        handleAlertActions
        handleDestinationDelegation
        handleInternalActions
        handleViewActions

        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Alert Handler

    private var handleAlertActions: ReduceChild<State, Action, PresentationAction<Action.Alert>> {
        ReduceChild(\.alert) { state, action in
            switch action {
            case .presented(.confirmDeleteTapped):
                guard let itemID = state.itemID else { return .none }
                state.isSaving = true
                return .run { [itemClient] send in
                    let result = await itemClient.delete(itemID)
                    await send(.internal(.deleteResponse(result)))
                }
                .cancellable(id: CancelID.delete)

            case .presented(.discardChangesTapped):
                return .run { [dismiss] _ in
                    await dismiss()
                }

            case .dismiss:
                return .none
            }
        }
    }

    // MARK: - Child Destination Delegation

    /// Handles delegate actions from presented child features.
    /// Uses `Reduce` because it matches across multiple destination types.
    private var handleDestinationDelegation: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.categoryPicker(.delegate(.selected(let category))))):
                state.category = category
                state.destination = nil
                return .none

            case .destination(.presented(.imagePicker(.delegate(.imageSelected(let data))))):
                state.imageData = data
                state.destination = nil
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
            case .deleteResponse(.success):
                state.isSaving = false
                guard let itemID = state.itemID else { return .none }
                /// Notify parent that deletion succeeded
                return .run { [dismiss] send in
                    await send(.delegate(.itemDeleted(itemID)))
                    await dismiss()
                }

            case .deleteResponse(.failure):
                /// Rollback: deletion failed, show error alert
                state.isSaving = false
                state.alert = AlertState {
                    TextState("Delete Failed")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Could not delete this item. Please try again.")
                }
                return .none

            case .saveResponse(.success(let savedItem)):
                state.isSaving = false
                /// Update the snapshot so "unsaved changes" detection resets
                state.originalItem = savedItem
                state.itemID = savedItem.id
                /// Notify parent of the saved item
                return .send(.delegate(.itemSaved(savedItem)))

            case .saveResponse(.failure):
                /// Rollback: optimistic title/price were already shown,
                /// but we keep them so the user can retry without retyping.
                state.isSaving = false
                state.alert = AlertState {
                    TextState("Save Failed")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Could not save your changes. Please try again.")
                }
                return .none

            case .validationCompleted:
                /// Validate all fields and update error map
                state.validationErrors = validate(state: state)
                return .none
            }
        }
    }

    // MARK: - View Handler

    private var handleViewActions: ReduceChild<State, Action, Action.View> {
        ReduceChild(\.view) { state, action in
            switch action {
            case .cancelButtonTapped:
                let hasChanges = state.title != (state.originalItem?.title ?? "")
                    || state.notes != (state.originalItem?.notes ?? "")
                    || state.price != state.originalItem?.price
                    || state.category != state.originalItem?.category

                if hasChanges {
                    state.alert = AlertState {
                        TextState("Discard Changes?")
                    } actions: {
                        ButtonState(role: .destructive, action: .discardChangesTapped) {
                            TextState("Discard")
                        }
                        ButtonState(role: .cancel) {
                            TextState("Keep Editing")
                        }
                    }
                    return .none
                } else {
                    return .run { [dismiss] _ in
                        await dismiss()
                    }
                }

            case .categoryFieldTapped:
                state.destination = .categoryPicker(
                    CategoryPickerFeature.State(selected: state.category)
                )
                return .none

            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("Delete Item?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeleteTapped) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("This action cannot be undone.")
                }
                return .none

            case .imagePickerButtonTapped:
                state.destination = .imagePicker(ImagePickerFeature.State())
                return .none

            case .onAppear:
                return .send(.internal(.validationCompleted))

            case .saveButtonTapped:
                /// Run validation first — block save if invalid
                let errors = validate(state: state)
                state.validationErrors = errors
                guard errors.isEmpty else {
                    /// Move focus to the first invalid field
                    state.focus = errors.keys.sorted(by: { "\($0)" < "\($1)" }).first
                    return .none
                }

                state.isSaving = true

                /// Capture specific values — NEVER capture `state` itself.
                /// This is G4 and G16: state is a value type, capturing it
                /// inside `.run` freezes a copy that can't be mutated.
                let title = state.title
                let notes = state.notes
                let price = state.price
                let category = state.category
                let itemID = state.itemID
                let imageData = state.imageData

                return .run { [itemClient, uuid] send in
                    let item = Item(
                        id: itemID ?? uuid().uuidString,
                        category: category,
                        imageData: imageData,
                        notes: notes,
                        price: price,
                        title: title
                    )
                    let result = await itemClient.save(item)
                    await send(.internal(.saveResponse(result)))
                }
                .cancellable(id: CancelID.save)
            }
        }
    }

    // MARK: - Validation

    /// Validation lives in the reducer — never in the view.
    /// Returns a dictionary of field → error message for inline display.
    private func validate(state: State) -> [Field: String] {
        var errors: [Field: String] = [:]

        if state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.title] = "Title is required"
        } else if state.title.count > 100 {
            errors[.title] = "Title must be under 100 characters"
        }

        if let price = state.price, price < 0 {
            errors[.price] = "Price cannot be negative"
        }

        return errors
    }
}

// MARK: - Item Editor View

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
                categorySection
                imageSection
                if store.itemID != nil {
                    deleteSection
                }
            }
            .navigationTitle(store.itemID == nil ? "New Item" : "Edit Item")
            .toolbar { toolbarContent }
            .alert($store.scope(state: \.alert, action: \.alert))
            /// Sheet for category picker — scoped at point of use
            .sheet(
                item: $store.scope(
                    state: \.destination?.categoryPicker,
                    action: \.destination.categoryPicker
                )
            ) { pickerStore in
                NavigationStack {
                    CategoryPickerView(store: pickerStore)
                }
            }
            /// Sheet for image picker
            .sheet(
                item: $store.scope(
                    state: \.destination?.imagePicker,
                    action: \.destination.imagePicker
                )
            ) { imageStore in
                ImagePickerView(store: imageStore)
            }
            /// Sync TCA focus state ↔ SwiftUI @FocusState
            .bind($store.focus, to: $focus)
            .disabled(store.isSaving)
            .task { send(.onAppear) }
        }
    }

    // MARK: - Form Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $store.title)
                .focused($focus, equals: .title)

            /// Inline validation error display
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

    private var categorySection: some View {
        Section("Category") {
            Button {
                send(.categoryFieldTapped)
            } label: {
                HStack {
                    Text(store.category?.name ?? "Select Category")
                        .foregroundStyle(store.category == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        Section("Image") {
            if store.imageData != nil {
                Text("Image attached")
                    .foregroundStyle(.secondary)
            }
            Button {
                send(.imagePickerButtonTapped)
            } label: {
                Label(
                    store.imageData == nil ? "Add Image" : "Change Image",
                    systemImage: "photo"
                )
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
                    Text("Delete Item")
                    Spacer()
                }
            }
        }
    }

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
