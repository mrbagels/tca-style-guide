# TCA/SwiftUI/SQLiteData Style Guide (LLM Reference)

## 1. Intro
Personal style guide for TCA+SwiftUI+SQLiteData apps. All code anonymized. "Feature" suffix is local convention (PFW says no suffix). Alphabetize everything: imports, actions, properties, enum cases, handlers. Use `///` for single-line docs, `/** */` for multi-line. Colors via Xcode asset catalog only.

## 2. Feature Pattern Template
```swift
import ComposableArchitecture
import SwiftUI

@Reducer struct ItemFeature {
  @ObservableState struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>?
    var isLoading = false
    var items: IdentifiedArrayOf<Item> = []
  }
  enum Action: ViewAction, BindableAction {
    case alert(PresentationAction<Alert>)
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case `internal`(Internal)
    case view(View)
    @CasePathable enum Alert: Sendable { case confirmDeleteTapped }
    @CasePathable enum Delegate: Sendable { case itemSaved(Item) }
    @CasePathable enum Internal: Sendable {
      case fetchResponse(Result<[Item], any Error>)
    }
    @CasePathable enum View: Sendable {
      case addButtonTapped
      case onAppear
    }
  }
  @Dependency(\.apiClient) var apiClient
  @Dependency(\.continuousClock) var clock
  var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding, .delegate: return .none
      default: return .none
      }
    }
    handleAlertActions
    handleInternalActions
    handleViewActions
    .ifLet(\.$alert, action: \.alert)
  }
  // ... ReduceChild handlers below
}
```
Key rules:
- `@ObservableState` on State, State: Equatable
- Action does NOT conform to Equatable (key path syntax needs no Equatable since TCA 1.4+)
- All nested action enums: `@CasePathable` + `Sendable`
- Name actions after user events: `saveButtonTapped` not `save`; effect results: `apiResponse` not `processData`
- `@Dependency` declared inside `@Reducer`, never outside
- Gotcha G4: Never mutate state inside `.run` closures—capture values, send actions back
- Gotcha G16: Always capture dependencies with `[apiClient]` in `.run` closures
- Gotcha G5: Always provide cancellation IDs for cancellable effects; missing `.cancellable(id:)` means `.cancel(id:)` does nothing

## 3. Action Organization
Alphabetical order in main enum: alert→binding→child→delegate→internal→view.

Nested enums:
- `View` (@CasePathable, Sendable): UI triggers (taps, gestures, onAppear). No logic.
- `Internal` (@CasePathable, Sendable): Business logic, API responses, timers.
- `Delegate` (@CasePathable, Sendable): Parent communication. Parent listens, never sends these.
- `Alert` (@CasePathable, Sendable): Alert button actions.

Gotcha G1: Never handle child delegate actions inside the child's own ReduceChild—handle them in the parent's reducer or a dedicated `handleChildDelegation` handler.

## 4. Reducer Body Structure
Order: BindingReducer → Scopes → Reduce (binding/delegate passthrough) → ReduceChild handlers → Presentations (.ifLet/.forEach)

Rationale:
1. BindingReducer first so bindings resolve before custom logic. Gotcha G2: BindingReducer MUST be first or binding changes won't be visible.
2. Scopes next for child state isolation.
3. Reduce for cross-cutting (binding/delegate passthrough only).
4. ReduceChild handlers for focused logic.
5. Presentations last—.ifLet/.forEach are modifiers. Gotcha G3: .ifLet/.forEach MUST come after the Reduce that mutates their state.

Do NOT use CombineReducers unless applying a modifier (.ifLet/.forEach) to the combined result.

## 5. ReduceChild Pattern
Custom helper replacing Reduce for focused action handling.

### 3 Variants
**ReduceChild** — focuses on child action type:
```swift
private var handleViewActions: ReduceChild<State, Action, Action.View> {
  ReduceChild(\.view) { state, action in
    switch action { // exhaustive over View cases only
    case .onAppear: return .send(.internal(.fetchData))
    }
  }
}
```
**ReduceChildWhen** — conditional processing:
```swift
private var handleAlertActions: ReduceChildWhen<State, Action, PresentationAction<Action.Alert>> {
  ReduceChildWhen(\.alert) { state, action in
    switch action {
    case .presented(.confirmDeleteTapped): ...
    case .dismiss: ...
    }
  }
}
```
**ReduceChildWithState** — projects parent state to a subset:
```swift
private var handleSectionActions: ReduceChildWithState<State, Action, Action.View, SectionState> {
  ReduceChildWithState(\.view, state: { SectionState(name: $0.name, email: $0.email) }) {
    sectionState, action in
    switch action { ... }
  }
}
```
Naming: `handle[Category]Actions` for direct, `handle[Child]Delegation` for child delegates.
Gotcha G1: Child delegate actions must be handled in the parent, not within the child's own ReduceChild handler.

## 6. View Organization
```swift
@ViewAction(for: ItemFeature.self)
struct ItemView: View {
  @Bindable var store: StoreOf<ItemFeature>
  var body: some View { content }
  private var content: some View { ... }
  private var headerSection: some View { ... }
  private var listSection: some View { ... }
}
```
Rules:
- `@ViewAction(for:)` macro on all TCA views; use `send(.actionName)` not `store.send(.view(.actionName))`
- `@Bindable var store` (not `let store`) when bindings needed
- Delegate body to private computed vars
- Extract subviews when >20 lines or reused
- Scope stores at point of use: `ChildView(store: store.scope(state: \.child, action: \.child))`
- Never use `Binding.init(get:set:)` — derive bindings via helpers on the Value type. Gotcha G10.
- Gotcha G8: For high-frequency actions (sliders, text fields), use `BindableAction` + `BindingReducer` instead of discrete actions to avoid performance issues.

## 7. Navigation & Routing
Two types: Stack (NavigationStack, StackState, push/pop) and Modal (@Presents, .sheet/.fullScreenCover, present/dismiss).

Router pattern: separate Path reducer enum + router feature:
```swift
@Reducer enum HomePath {
  case detail(DetailFeature)
  case settings(SettingsFeature)
}
@Reducer struct HomeRouter {
  @ObservableState struct State: Equatable {
    @Presents var destination: Destination.State?
    var home: HomeFeature.State
    var path: StackState<HomePath.State> = []
  }
  enum Action: ViewAction, BindableAction {
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case destination(PresentationAction<Destination.Action>)
    case home(HomeFeature.Action)
    case `internal`(Internal)
    case path(StackActionOf<HomePath>)
    case view(View)
    // nested enums...
  }
  var body: some ReducerOf<Self> {
    Scope(state: \.home, action: \.home) { HomeFeature() }
    Reduce { state, action in
      switch action {
      case .binding, .delegate: return .none
      default: return .none
      }
    }
    handleViewActions
    handleInternalActions
    handleChildDelegation // may use Reduce for complex cross-feature delegation
    .forEach(\.path, action: \.path)
    .ifLet(\.$destination, action: \.destination)
  }
}
```
Gotcha G12: NavigationLink evaluates destination view eagerly—all destination dependencies must be available at parent render time.
Gotcha G6: Avoid action ping-pong (action→effect→action→effect chains). Prefer direct state mutation.
Gotcha G9: `.cancelInFlight` replaces any pending effect with same ID. Use separate CancelIDs if effects should coexist.

ContentView pattern for router views:
```swift
struct HomeRouterView: View {
  @Bindable var store: StoreOf<HomeRouter>
  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      HomeView(store: store.scope(state: \.home, action: \.home))
    } destination: { pathStore in
      switch pathStore.case {
      case .detail(let s): DetailView(store: s)
      case .settings(let s): SettingsView(store: s)
      }
    }
  }
}
```

## 8. State Management
**@ObservableState**: Always on State struct. Gotcha G11: `didSet` on @ObservableState properties can cause infinite loops—use `onChange(of:)` or handle in reducer instead.

**@Shared**: Reference-type semantics for cross-feature state.
```swift
@Shared(.appStorage("hasOnboarded")) var hasOnboarded = false
@Shared(.inMemory("currentUser")) var currentUser: User?
```
Mutate with `.withLock { $0.field = value }`. Gotcha G7: @Shared has reference semantics—mutations in one feature are immediately visible everywhere. Always use `.withLock` for thread safety.

**@Presents**: For optional child features (sheets, alerts, fullscreen covers).

**IdentifiedArrayOf**: For collections of identifiable child features.

## 9. Dependencies
Define with `@DependencyClient`:
```swift
@DependencyClient struct APIClient: Sendable {
  var fetchItems: @Sendable () async throws -> [Item]
  var saveItem: @Sendable (Item) async throws -> Item
}
extension APIClient: TestDependencyKey {
  static let testValue = APIClient()
}
```
File organization: `APIClient.swift` (interface), `APIClient+Live.swift` (DependencyKey conformance), `Endpoints/` (endpoint details).

Register: `extension APIClient: DependencyKey { static var liveValue: APIClient { ... } }`
Access: `@Dependency(APIClient.self) var apiClient` or `@Dependency(\.apiClient) var apiClient`
Always use controlled deps over uncontrolled: `@Dependency(\.uuid) var uuid` + `uuid()` not `UUID()`.

## 10. SQLiteData & Persistence

### 10.1 Model Definition
```swift
import SQLiteData
@Table struct Item: Identifiable, Sendable {
  var id: Tagged<Self, UUID>
  var body: String
  var createdAt: Date
  var isCompleted: Bool
  var title: String
}
```
Use `Tagged<Self, UUID>` for type-safe IDs. @Table generates conformances. Mark all models `Sendable`.

### 10.2 Database Setup
```swift
extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("v1") { db in
      try #sql("CREATE TABLE IF NOT EXISTS \"item\" (\"id\" TEXT PRIMARY KEY NOT NULL, \"body\" TEXT NOT NULL, \"createdAt\" DATETIME NOT NULL, \"isCompleted\" BOOLEAN NOT NULL DEFAULT 0, \"title\" TEXT NOT NULL)", execute: db)
    }
    try migrator.migrate(database)
    defaultDatabase = database
  }
}
```
Call in app entry: `init() { prepareDependencies { try! $0.bootstrapDatabase() } }`

### 10.3 Migrations
Use `#sql` macro. Each migration is a string identifier registered on DatabaseMigrator. Never modify past migrations—add new ones. Use `eraseDatabaseOnSchemaChange = true` in DEBUG only.
```swift
migrator.registerMigration("v2-add-priority") { db in
  try #sql("ALTER TABLE \"item\" ADD COLUMN \"priority\" INTEGER NOT NULL DEFAULT 0", execute: db)
}
```

### 10.4 CRUD
```swift
// Read
let items = try await database.read { db in try Item.fetchAll(db) }
let item = try await database.read { db in try Item.find(itemID).fetchOne(db) }
let count = try await database.read { db in try Item.where(\.isCompleted).fetchCount(db) }
// Write
try database.write { db in try Item.insert { $0.id = id; $0.title = title; ... }.execute(db) }
try database.write { db in try Item.find(itemID).update { $0.isCompleted = true }.execute(db) }
try database.write { db in try Item.find(itemID).delete().execute(db) }
```
Use `await` for async context. Wrap in `withErrorReporting { }`. Never fatalError on DB errors.

### 10.5 Observation
`@FetchAll` for many rows, `@FetchOne` for single/aggregate, `@Fetch` with `FetchKeyRequest` for multi-query.
```swift
@FetchAll var items: [Item]
@FetchAll(Item.where(\.isCompleted)) var completed
@FetchOne(Item.count()) var itemCount = 0
```
Dynamic queries: init with `.none`, load in `.task`:
```swift
@FetchAll(Item.none) var items
// in .task:
try await $items.load(Item.where { $0.listID.eq(listID) }, animation: .default)
```
Gotcha G13: `withAnimation` around DB writes does NOT work. Use `animation:` parameter on @FetchAll or `$items.load(..., animation:)`.

### 10.6 @Selection
For efficient queries selecting only needed columns:
```swift
@Selection struct Row: Identifiable {
  var id: Item.ID
  var title: String
  var listName: String
}
@FetchAll(
  Item.join(ItemList.all) { .listID.eq(.id) }
    .select { Row.Columns(id: .id, title: .title, listName: .title) }
) var rows
```

### 10.7 Joins
```swift
// INNER JOIN
Item.join(ItemList.all) { .listID.eq(.id) }
// LEFT JOIN
Item.leftJoin(Tag.all) { .tagID.eq(.id) }
// Multiple joins chain
Item.join(ItemList.all) { .listID.eq(.id) }.join(Category.all) { .categoryID.eq(.id) }
```

### 10.8 Aggregation
```swift
Item.count() // total count
Item.where(\.isCompleted).count() // filtered count
Item.select { .max(.priority) } // max value
Item.group(by: \.listID).select { (.listID, .count()) } // group+count
```

### 10.9 Computed Query Expressions
```swift
Item.where { $0.title.like("%search%") }
Item.where { $0.priority.gt(5) }
Item.where { $0.createdAt.lt(Date()) }
Item.where { $0.title.isNotNull }
Item.order { $0.createdAt.desc() }
```

### 10.10 Draft Types
Drafts have optional ID. nil=never inserted, non-nil=not yet saved.
```swift
@State var draft = Item.Draft()
func save() {
  try database.write { db in try Item.upsert { draft }.execute(db) }
}
```
Drafts are NOT Identifiable by default (multiple can have nil id).

### 10.11 iCloud Sync
Uses SyncEngine. Setup:
```swift
let syncEngine = SyncEngine(
  database: database,
  configuration: SyncEngine.Configuration(containerIdentifier: "iCloud.com.app.name")
)
```
Register in bootstrapDatabase. Filter sync-related SQL logging. Conflict resolution uses server-wins by default.

### 10.12 Testing
```swift
@Suite(.dependencies { try! $0.bootstrapDatabase() })
struct ItemTests {
  @Dependency(\.defaultDatabase) var database
  @Test func createItem() async throws {
    try database.write { db in
      try Item.insert { $0.id = ...; $0.title = "Test" }.execute(db)
    }
    let items = try await database.read { db in try Item.fetchAll(db) }
    #expect(items.count == 1)
  }
}
```
Use `.dependencies` trait to bootstrap. Each test gets isolated DB state with eraseDatabaseOnSchemaChange.

## 11. Naming Conventions
| Entity | Convention | Example |
|---|---|---|
| Feature | `[Name]Feature` | `AccountSettingsFeature` |
| View | `[Name]View` | `AccountSettingsView` |
| Router | `[Name]Router` | `HomeRouter` |
| Path | `[Parent]Path` | `HomePath` |
| Destination | `Destination` (nested) | `Destination.State` |
| Client | `[Name]Client` | `APIClient` |
| Live impl | `[Name]Client+Live.swift` | `APIClient+Live.swift` |
| Handler | `handle[Category]Actions` | `handleViewActions` |
| Delegate handler | `handle[Child]Delegation` | `handleHomeDelegation` |
| View action | `[noun][Verb]ed/Tapped` | `saveButtonTapped`, `onAppear` |
| Internal action | `[noun]Response/Tick/Completed` | `fetchResponse`, `timerTick` |
| Delegate action | `[noun][Verb]ed` | `itemSaved`, `selectionChanged` |

## 12. Code Style
- Imports: alphabetical, SwiftLint `sorted_imports` enforced
- Access: `public` at package boundaries, `private` for implementation
- `// MARK: -` for section organization
- Colors: Xcode asset catalogs. Only use Color extensions for computed functionality (lighter/darker), not definitions
- Alphabetize everything: imports, action cases, State properties, switch cases, handler declarations

## 13. Testing
Apple Testing framework: `@Suite`, `@Test`, `#expect`, `#require`.

TCA test pattern:
```swift
@Test(.dependencies { $0.apiClient.fetchItems = { [Item.mock] } })
func fetchItems() async {
  let store = TestStore(initialState: ItemFeature.State()) { ItemFeature() }
  await store.send(.view(.onAppear)) { $0.isLoading = true }
  await store.receive(\.internal.fetchResponse.success) { $0.isLoading = false; $0.items = [.mock] }
}
```
Key path receive syntax: `store.receive(\.internal.fetchResponse.success)`.
Use `.dependencies {}` test trait (preferred over withDependencies).
Use `expectNoDifference` / `expectDifference` from CustomDump.
Non-exhaustive testing: `store.exhaustivity = .off` for integration-level tests.
Gotcha G14: Always use `TestClock`/`ImmediateClock` for time-dependent tests—never `ContinuousClock`.
Gotcha G15: Tests run inside the real app process. Guard app entry point: `if !_XCTIsTesting { prepareDependencies { ... } }` or similar check to prevent real DB/network during tests.

## 14. Gotchas Quick Reference
G1: Handle child delegate actions in parent, not child's own reducer.
G2: BindingReducer must be first in body.
G3: .ifLet/.forEach must come after the Reduce that mutates their state.
G4: Never mutate state inside .run closures—capture values, send actions back.
G5: Always add .cancellable(id:) to effects you want to cancel later.
G6: Avoid action ping-pong chains; prefer direct state mutation.
G7: @Shared has reference semantics, mutations visible everywhere immediately. Use .withLock.
G8: Use BindingReducer for high-frequency UI (sliders, text). Discrete actions per keystroke = perf issues.
G9: .cancelInFlight replaces pending effects with same ID. Use separate IDs for coexisting effects.
G10: Never use Binding.init(get:set:). Derive bindings via Value type extensions.
G11: didSet on @ObservableState properties → infinite loops. Use onChange(of:) or reducer logic.
G12: NavigationLink evaluates destinations eagerly. All deps must exist at parent render time.
G13: withAnimation around DB writes doesn't work. Use animation: parameter on @FetchAll/load.
G14: Use TestClock/ImmediateClock for time tests, never ContinuousClock.
G15: Tests run in app process. Guard entry point against real bootstrapping.
G16: Capture dependencies in .run closure capture lists: `[apiClient]`.

## 15. Extensions Starter Kit

### View
```swift
extension View {
  func loadingOverlay(_ isLoading: Bool) -> some View {
    overlay { if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) } }
  }
  func shimmerEffect(_ active: Bool = true) -> some View {
    modifier(ShimmerModifier(isActive: active))
  }
  func pressEffect(_ isPressed: Bool) -> some View {
    scaleEffect(isPressed ? 0.97 : 1.0).opacity(isPressed ? 0.9 : 1.0).animation(.easeInOut(duration: 0.15), value: isPressed)
  }
  func cardStyle(cornerRadius: CGFloat = 12, shadowRadius: CGFloat = 4) -> some View {
    background(Color(.systemBackground)).cornerRadius(cornerRadius).shadow(color: .black.opacity(0.1), radius: shadowRadius, x: 0, y: 2)
  }
  func fieldStyle() -> some View {
    padding(.horizontal, 16).padding(.vertical, 12).background(Color(.secondarySystemBackground)).cornerRadius(10)
  }
  func separator(color: Color = Color(.separator), height: CGFloat = 0.5) -> some View {
    overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: height) }
  }
  func dismissKeyboardOnTap() -> some View {
    onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
  }
  @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition { transform(self) } else { self }
  }
  func onFirstAppear(perform action: @escaping () -> Void) -> some View {
    modifier(FirstAppearModifier(action: action))
  }
  func fadeOverlay(_ show: Bool, color: Color = .black.opacity(0.4)) -> some View {
    overlay { if show { color.ignoresSafeArea().transition(.opacity) } }
  }
  func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
    background(GeometryReader { g in Color.clear.preference(key: SizePreferenceKey.self, value: g.size) }).onPreferenceChange(SizePreferenceKey.self, perform: onChange)
  }
  func fillWidth(alignment: Alignment = .center) -> some View { frame(maxWidth: .infinity, alignment: alignment) }
  func fillHeight(alignment: Alignment = .center) -> some View { frame(maxHeight: .infinity, alignment: alignment) }
  func fillSpace(alignment: Alignment = .center) -> some View { frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment) }
  func onTapWithHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, action: @escaping () -> Void) -> some View {
    onTapGesture { UIImpactFeedbackGenerator(style: style).impactOccurred(); action() }
  }
  func debugBorder(_ color: Color = .red) -> some View { #if DEBUG; border(color); #else; self; #endif }
  @ViewBuilder func hidden(_ isHidden: Bool) -> some View { if isHidden { self.hidden() } else { self } }
  func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
    self.mask(Rectangle().overlay(alignment: .center) { mask().blendMode(.destinationOut) })
  }
  func accessibleButton(label: String, hint: String? = nil) -> some View {
    accessibilityLabel(label).accessibilityAddTraits(.isButton).if(hint != nil) { $0.accessibilityHint(hint!) }
  }
}
```
Supporting types:
```swift
struct ShimmerModifier: ViewModifier {
  let isActive: Bool
  @State private var phase: CGFloat = 0
  func body(content: Content) -> some View {
    content.overlay(isActive ? LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing).offset(x: phase).mask(content) : nil)
      .onAppear { guard isActive else { return }; withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = UIScreen.main.bounds.width } }
  }
}
struct FirstAppearModifier: ViewModifier {
  let action: () -> Void
  @State private var hasAppeared = false
  func body(content: Content) -> some View {
    content.onAppear { guard !hasAppeared else { return }; hasAppeared = true; action() }
  }
}
private struct SizePreferenceKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
```

### String
```swift
extension String {
  var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var urlEncoded: String? { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
  var isValidEmail: Bool { matches(pattern: "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$") }
  func maskedEmail() -> String {
    guard let at = firstIndex(of: "@") else { return self }
    let local = String(prefix(upTo: at))
    return (local.count <= 2 ? local : String(local.prefix(2)) + String(repeating: "*", count: max(local.count - 2, 0))) + suffix(from: at)
  }
  func maskedPhone(visibleDigits: Int = 4) -> String {
    let digits = filter(\.isNumber)
    guard digits.count > visibleDigits else { return self }
    return String(repeating: "*", count: digits.count - visibleDigits) + digits.suffix(visibleDigits)
  }
  var initials: String { split(separator: " ").compactMap { $0.first.map(String.init) }.prefix(2).joined().uppercased() }
  var wordCount: Int { split(separator: " ").count }
  func truncated(to max: Int, trailing: String = "...") -> String { count > max ? String(prefix(max)) + trailing : self }
  var containsOnlyDigits: Bool { !isEmpty && allSatisfy(\.isNumber) }
  func matches(pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
  var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
  var snakeCased: String { (try? NSRegularExpression(pattern: "([a-z0-9])([A-Z])")).map { $0.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "$1_$2") }?.lowercased() ?? lowercased() }
}
extension Optional where Wrapped == String {
  var orEmpty: String { self ?? "" }
}
```

### Date
```swift
extension Date {
  func adding(_ component: Calendar.Component, value: Int) -> Date { Calendar.current.date(byAdding: component, value: value, to: self)! }
  var isToday: Bool { Calendar.current.isDateInToday(self) }
  var startOfDay: Date { Calendar.current.startOfDay(for: self) }
  var endOfDay: Date { adding(.day, value: 1).startOfDay.addingTimeInterval(-1) }
  var relativeTimeString: String { RelativeDateTimeFormatter().localizedString(for: self, relativeTo: Date()) }
  var shortRelativeTimeString: String { let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f.localizedString(for: self, relativeTo: Date()) }
  var year: Int { Calendar.current.component(.year, from: self) }
  var month: Int { Calendar.current.component(.month, from: self) }
  var day: Int { Calendar.current.component(.day, from: self) }
  var isWeekend: Bool { Calendar.current.isDateInWeekend(self) }
  var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }
  var isTomorrow: Bool { Calendar.current.isDateInTomorrow(self) }
  var isInPast: Bool { self < Date() }
  var isInFuture: Bool { self > Date() }
  func days(until other: Date) -> Int { Calendar.current.dateComponents([.day], from: self, to: other).day ?? 0 }
  var ageInYears: Int { Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0 }
}
```

### DateFormatter
```swift
extension DateFormatter {
  static let shortDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; return f }()
  static let mediumDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
  static let fullDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .full; return f }()
  static let timeOnly: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
  static let iso8601: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
  static let monthYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
  static let dayMonth: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f }()
}
```

### Number
```swift
extension Double {
  func currencyFormatted(code: String = "USD") -> String { formatted(.currency(code: code)) }
  var percentFormatted: String { formatted(.percent.precision(.fractionLength(0...1))) }
  var twoDecimalPlaces: String { String(format: "%.2f", self) }
}
extension Decimal {
  func currencyFormatted(code: String = "USD") -> String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = code
    return f.string(from: self as NSDecimalNumber) ?? "\(self)"
  }
}
extension Int {
  var ordinalString: String { NumberFormatter().then { $0.numberStyle = .ordinal }.string(from: NSNumber(value: self)) ?? "\(self)" }
  var abbreviated: String { formatted(.number.notation(.compactName)) }
  var formattedDuration: String {
    let h = self / 3600, m = (self % 3600) / 60, s = self % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
  var seconds: TimeInterval { TimeInterval(self) }
  var minutes: TimeInterval { TimeInterval(self) * 60 }
  var hours: TimeInterval { TimeInterval(self) * 3600 }
}
```

### Collection
```swift
extension Collection {
  subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
extension Array {
  func chunked(into size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
  var nonEmpty: Self? { isEmpty ? nil : self }
}
extension Sequence where Element: Hashable {
  var unique: [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
extension Sequence {
  func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>, ascending: Bool = true) -> [Element] {
    sorted { ascending ? $0[keyPath: keyPath] < $1[keyPath: keyPath] : $0[keyPath: keyPath] > $1[keyPath: keyPath] }
  }
  func grouped<Key: Hashable>(by key: (Element) -> Key) -> [Key: [Element]] { Dictionary(grouping: self, by: key) }
}
extension Sequence where Element: Numeric { var sum: Element { reduce(0, +) } }
extension Sequence {
  func sum<T: Numeric>(of keyPath: KeyPath<Element, T>) -> T { reduce(T.zero) { $0 + $1[keyPath: keyPath] } }
}
```

### Optional
```swift
extension Optional {
  var isNil: Bool { self == nil }
  var isNotNil: Bool { self != nil }
  func unwrapOrThrow(_ error: @autoclosure () -> Error) throws -> Wrapped { guard let v = self else { throw error() }; return v }
}
extension Optional where Wrapped: Collection {
  var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
```

### Encodable
```swift
extension Encodable {
  func toData() throws -> Data { try JSONEncoder().encode(self) }
  func toJSONString() throws -> String { String(decoding: try toData(), as: UTF8.self) }
  func toPrettyJSONString() throws -> String { let e = JSONEncoder(); e.outputFormatting = .prettyPrinted; return String(decoding: try e.encode(self), as: UTF8.self) }
  func toDictionary() throws -> [String: Any] { try JSONSerialization.jsonObject(with: toData()) as? [String: Any] ?? [:] }
  var asData: Data? { try? toData() }
  var asJSONString: String? { try? toJSONString() }
}
```

### URL
```swift
extension URL {
  static var documentsPath: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! }
  static func documentsPath(for key: String) -> URL { documentsPath.appendingPathComponent(key) }
}
```

### EdgeInsets
```swift
extension EdgeInsets {
  static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
  init(all value: CGFloat) { self.init(top: value, leading: value, bottom: value, trailing: value) }
  init(horizontal: CGFloat = 0, vertical: CGFloat = 0) { self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal) }
}
```

### Result
```swift
extension Result {
  var success: Success? { if case .success(let v) = self { return v }; return nil }
  var failure: Failure? { if case .failure(let e) = self { return e }; return nil }
  var isSuccess: Bool { success != nil }
  var isFailure: Bool { failure != nil }
}
```

### Comparable
```swift
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
```

### Bundle
```swift
extension Bundle {
  var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }
  var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "0" }
  var fullVersionString: String { "\(appVersion) (\(buildNumber))" }
  var displayName: String { infoDictionary?["CFBundleDisplayName"] as? String ?? infoDictionary?["CFBundleName"] as? String ?? "Unknown" }
}
```

### Data
```swift
extension Data {
  var hexString: String { map { String(format: "%02x", $0) }.joined() }
  var prettyPrintedJSON: String {
    guard let obj = try? JSONSerialization.jsonObject(with: self), let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), let s = String(data: d, encoding: .utf8) else { return String(data: self, encoding: .utf8) ?? "" }
    return s
  }
  var fileSizeDescription: String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
}
```

### Color
```swift
extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: (a,r,g,b) = (255,(int>>8)*17,(int>>4&0xF)*17,(int&0xF)*17)
    case 6: (a,r,g,b) = (255,int>>16,int>>8&0xFF,int&0xFF)
    case 8: (a,r,g,b) = (int>>24,int>>16&0xFF,int>>8&0xFF,int&0xFF)
    default: (a,r,g,b) = (255,0,0,0)
    }
    self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
  }
  func lighter(by pct: Double = 0.1) -> Color { adjustBrightness(by: abs(pct)) }
  func darker(by pct: Double = 0.1) -> Color { adjustBrightness(by: -abs(pct)) }
  private func adjustBrightness(by amount: Double) -> Color {
    guard let c = UIColor(self).hsba else { return self }
    return Color(hue: c.hue, saturation: c.saturation, brightness: min(max(c.brightness + amount, 0), 1), opacity: c.alpha)
  }
}
```

### Animation
```swift
extension Animation {
  static let gentle: Animation = .easeInOut(duration: 0.25)
  static let standard: Animation = .easeInOut(duration: 0.35)
  static let quickSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
  static let bouncySpring: Animation = .spring(response: 0.5, dampingFraction: 0.5)
  static let smoothSpring: Animation = .spring(response: 0.4, dampingFraction: 1.0)
  func staggered(index: Int, delayPerItem: Double = 0.05) -> Animation { delay(Double(index) * delayPerItem) }
}
```

### UIImage
```swift
extension UIImage {
  func resized(toWidth w: CGFloat) -> UIImage {
    let s = w / size.width; let h = size.height * s
    return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in draw(in: CGRect(origin: .zero, size: CGSize(width: w, height: h))) }
  }
  func compressed(maxKB: Int = 500) -> Data? {
    var c: CGFloat = 1.0; var d = jpegData(compressionQuality: c)
    while let data = d, data.count > maxKB * 1024, c > 0.1 { c -= 0.1; d = jpegData(compressionQuality: c) }
    return d
  }
}
```

### Misc
```swift
extension Dictionary { func mapKeys<T: Hashable>(_ t: (Key) -> T) -> [T: Value] { reduce(into: [:]) { $0[t($1.key)] = $1.value } } }
extension Task where Success == Never, Failure == Never {
  static func sleep(for d: Duration) async throws { try await sleep(nanoseconds: UInt64(d.components.seconds * 1_000_000_000 + d.components.attoseconds / 1_000_000_000)) }
}
extension UIApplication { func endEditing() { sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
extension Notification.Name {
  static let userDidLogin = Notification.Name("app.userDidLogin")
  static let userDidLogout = Notification.Name("app.userDidLogout")
}
```

### EnvironmentValues Pattern
```swift
private struct ThemeOverrideKey: EnvironmentKey { static let defaultValue: ColorScheme? = nil }
extension EnvironmentValues {
  var themeOverride: ColorScheme? { get { self[ThemeOverrideKey.self] } set { self[ThemeOverrideKey.self] = newValue } }
}
extension View { func themeOverride(_ theme: ColorScheme?) -> some View { environment(\.themeOverride, theme) } }
```

## Checklist: New Feature
- [ ] `[Name]Feature.swift` with @Reducer
- [ ] @ObservableState State: Equatable (no Equatable on Action)
- [ ] Actions: alert→binding→delegate→internal→view (alphabetical)
- [ ] @CasePathable + Sendable on nested action enums
- [ ] @Dependency inside @Reducer
- [ ] Body: BindingReducer→Scopes→Reduce→Handlers→Presentations
- [ ] ReduceChild for each action category
- [ ] `[Name]View.swift` with @ViewAction(for:)
- [ ] @Bindable var store
- [ ] Delegate body to private computed properties
- [ ] Scope stores at point of use
- [ ] Tests: @Suite, @Test, #expect, .dependencies{} trait
- [ ] Key path receive: store.receive(\.internal.response.success)
- [ ] Alphabetize everything