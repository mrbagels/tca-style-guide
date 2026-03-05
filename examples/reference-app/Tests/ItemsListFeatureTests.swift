/// # Items List Feature Tests
/// @topic testing
///
/// Tests for `ItemsListFeature` demonstrating:
/// - Fetch on appear with loading state
/// - Pull-to-refresh
/// - Swipe-to-delete with optimistic removal
/// - Delegate action verification for router communication
///
/// ## Key Rules
/// - `TestStore` for exhaustive state assertion
/// - Override dependencies via `withDependencies`
/// - Case key path syntax for `.receive()` — no `Equatable` on Action
/// - Verify delegate actions to confirm parent communication contracts

import ComposableArchitecture
import IdentifiedCollections
import Testing

@Suite("ItemsListFeature Tests")
struct ItemsListFeatureTests {

    // MARK: - Fetch

    @Test("Items load on appear")
    func itemsLoadOnAppear() async {
        let store = TestStore(initialState: ItemsListFeature.State()) {
            ItemsListFeature()
        } withDependencies: {
            $0.itemClient.fetchAll = { Item.samples }
        }

        await store.send(.view(.onAppear)) {
            $0.isLoading = true
        }

        await store.receive(\.internal.fetchResponse.success) {
            $0.isLoading = false
            $0.items = Item.samples
        }
    }

    @Test("Fetch failure clears loading state")
    func fetchFailureClearsLoading() async {
        let store = TestStore(initialState: ItemsListFeature.State()) {
            ItemsListFeature()
        } withDependencies: {
            $0.itemClient.fetchAll = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.view(.onAppear)) {
            $0.isLoading = true
        }

        await store.receive(\.internal.fetchResponse.failure) {
            $0.isLoading = false
        }
    }

    // MARK: - Refresh

    @Test("Pull-to-refresh reloads items")
    func pullToRefreshReloadsItems() async {
        let updatedItems: IdentifiedArrayOf<Item> = [Item.preview]

        let store = TestStore(
            initialState: ItemsListFeature.State(items: Item.samples)
        ) {
            ItemsListFeature()
        } withDependencies: {
            $0.itemClient.fetchAll = { updatedItems }
        }

        await store.send(.view(.refreshTriggered))

        await store.receive(\.internal.fetchResponse.success) {
            $0.items = updatedItems
        }
    }

    // MARK: - Delete

    @Test("Swipe-to-delete removes item on success")
    func swipeToDeleteRemovesItem() async {
        let itemToDelete = Item.samples[0]

        let store = TestStore(
            initialState: ItemsListFeature.State(items: Item.samples)
        ) {
            ItemsListFeature()
        } withDependencies: {
            $0.itemClient.delete = { _ in }
        }

        await store.send(.view(.deleteSwipeTapped(itemToDelete.id)))

        await store.receive(\.internal.deleteResponse) {
            $0.items.remove(id: itemToDelete.id)
        }
    }

    @Test("Delete failure keeps item in list")
    func deleteFailureKeepsItem() async {
        let itemToDelete = Item.samples[0]

        let store = TestStore(
            initialState: ItemsListFeature.State(items: Item.samples)
        ) {
            ItemsListFeature()
        } withDependencies: {
            $0.itemClient.delete = { _ in throw NSError(domain: "test", code: -1) }
        }

        await store.send(.view(.deleteSwipeTapped(itemToDelete.id)))

        /// On failure, state is unchanged — item stays in list
        await store.receive(\.internal.deleteResponse)
    }

    // MARK: - Delegates

    @Test("Add button sends delegate action")
    func addButtonSendsDelegate() async {
        let store = TestStore(initialState: ItemsListFeature.State()) {
            ItemsListFeature()
        }

        await store.send(.view(.addButtonTapped))
        await store.receive(\.delegate.addItemTapped)
    }

    @Test("Item row tap sends delegate with item")
    func itemRowTapSendsDelegate() async {
        let item = Item.preview

        let store = TestStore(initialState: ItemsListFeature.State()) {
            ItemsListFeature()
        }

        await store.send(.view(.itemRowTapped(item)))
        await store.receive(\.delegate.itemSelected)
    }
}
