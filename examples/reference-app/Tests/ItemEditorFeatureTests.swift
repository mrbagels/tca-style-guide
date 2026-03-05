/// # Item Editor Feature Tests
/// @topic testing
///
/// Tests for `ItemEditorFeature` demonstrating:
/// - Validation rejection for empty title
/// - Successful save flow with delegate
/// - Save failure with error alert
/// - Cancel with unsaved changes confirmation
///
/// ## Key Rules
/// - `TestStore` for exhaustive state assertion
/// - Override `uuid` dependency for deterministic IDs
/// - Use `AlertState` assertion for alert presentation
/// - Verify delegate actions for parent communication

import ComposableArchitecture
import Testing

@Suite("ItemEditorFeature Tests")
struct ItemEditorFeatureTests {

    // MARK: - Validation

    @Test("Save rejected when title is empty")
    func saveRejectedWhenTitleEmpty() async {
        let store = TestStore(initialState: ItemEditorFeature.State()) {
            ItemEditorFeature()
        }

        await store.send(.view(.saveButtonTapped))

        await store.receive(\.internal.validationCompleted) {
            $0.validationErrors = [.titleRequired]
        }
    }

    @Test("Save rejected when title is whitespace only")
    func saveRejectedWhenTitleWhitespace() async {
        var state = ItemEditorFeature.State()
        state.title = "   "

        let store = TestStore(initialState: state) {
            ItemEditorFeature()
        }

        await store.send(.view(.saveButtonTapped))

        await store.receive(\.internal.validationCompleted) {
            $0.validationErrors = [.titleRequired]
        }
    }

    // MARK: - Save Success

    @Test("Save success sends delegate and dismisses")
    func saveSuccessSendsDelegate() async {
        var state = ItemEditorFeature.State()
        state.title = "Test Item"
        state.notes = "Some notes"

        let store = TestStore(initialState: state) {
            ItemEditorFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
            $0.itemClient.save = { item in item }
            $0.uuid = .incrementing
        }

        await store.send(.view(.saveButtonTapped))

        await store.receive(\.internal.validationCompleted) {
            $0.isSaving = true
        }

        await store.receive(\.internal.saveResponse.success) {
            $0.isSaving = false
        }

        await store.receive(\.delegate.itemSaved)
    }

    // MARK: - Save Failure

    @Test("Save failure shows error alert")
    func saveFailureShowsAlert() async {
        var state = ItemEditorFeature.State()
        state.title = "Test Item"

        let store = TestStore(initialState: state) {
            ItemEditorFeature()
        } withDependencies: {
            $0.itemClient.save = { _ in throw NSError(domain: "test", code: -1) }
            $0.uuid = .incrementing
        }

        await store.send(.view(.saveButtonTapped))

        await store.receive(\.internal.validationCompleted) {
            $0.isSaving = true
        }

        await store.receive(\.internal.saveResponse.failure) {
            $0.alert = AlertState {
                TextState("Save Failed")
            } actions: {
                ButtonState(role: .cancel) {
                    TextState("OK")
                }
            } message: {
                TextState("Could not save the item. Please try again.")
            }
            $0.isSaving = false
        }
    }

    // MARK: - Cancel

    @Test("Cancel with changes shows confirmation alert")
    func cancelWithChangesShowsAlert() async {
        var state = ItemEditorFeature.State()
        state.title = "Unsaved changes"

        let store = TestStore(initialState: state) {
            ItemEditorFeature()
        }

        await store.send(.view(.cancelButtonTapped)) {
            $0.alert = AlertState {
                TextState("Discard Changes?")
            } actions: {
                ButtonState(role: .destructive, action: .discardChangesTapped) {
                    TextState("Discard")
                }
                ButtonState(role: .cancel) {
                    TextState("Keep Editing")
                }
            }
        }
    }

    @Test("Cancel without changes dismisses immediately")
    func cancelWithoutChangesDismisses() async {
        let store = TestStore(initialState: ItemEditorFeature.State()) {
            ItemEditorFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
        }

        await store.send(.view(.cancelButtonTapped))
    }
}
