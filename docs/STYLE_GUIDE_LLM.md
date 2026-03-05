# TCA_ARCH_SPEC_LLM_INJECTION

ARCH_VERSION=1.0 TARGET=TCA+SwiftUI+SQLiteData

GLOBAL: CONSISTENCY\>cleverness
ALPHABETIZE=imports,enum_cases,handlers,properties
EXHAUSTIVE_SWITCH=preferred COMPOSITION\>monolith TEST_BY_DEFAULT=true

FEATURE: @Reducer struct XFeature @ObservableState State:Equatable
Action:ViewAction(+BindableAction_if_needed) NO_Action:Equatable
Dependencies=inside_reducer INIT=public_empty

ACTION_TOP_LEVEL(alpha):
alert,binding,child,delegate,destination,internal,path,view

ACTION_NESTED: @CasePathable Sendable alpha_order

PARENT_RULE: parent\<=child.delegate parent!=child.view
parent!=child.internal

REDUCER_ORDER: BindingReducer Scope Reduce_passthrough_only
ReduceChild_handlers .ifLet/.forEach_last

REDUCECHILD: 1_per_action_category NO_parent_child_internal_send

VIEW: @ViewAction @Bindable_store minimal_body private_subviews
scope_at_use NO_Binding(get:set) avoid_high_freq_actions

ROUTER: root+path+destination Scope_root .forEach_path
.ifLet_destination NO_nav_state_in_view

STATE: @ObservableState NO_property_observers
@Shared=reference_semantics(use_withLock) @Presents=optional_child

DEPENDENCIES: @DependencyClient +Live_file TestDependencyKey_required
declare_inside_reducer

SQLITEDATA: @Table_singular DB_plural NON_NULL_requires_DEFAULT
MIGRATIONS=#sql_only NO_edit_shipped_migrations
SCHEMA_REWRITE=Create-Copy-Drop-Rename
Fetch_animation=animation_param_only

SYNC: explicit_tables_only NO_compound_PK NO_unique_indexes_except_PK
NO_reserved_iCloud_columns NO_many_to_many_sharing

TESTING: SwiftTesting_framework override_continuousClock
negative_UUID_tests positive_UUID_previews guard\_!\_XCTIsTesting
exhaustivity_optional

GOTCHAS: G1 parent!=child.view/internal G2 missing_BindingReducer G3
missing_ifLet_forEach G4 state_mutation_in_effect G5
uncancelled_long_effects G6 action_ping_pong G7
Shared_reference_semantics G8 high_freq_actions G9
cancelInFlight_static_ID G10 Binding_get_set G11 property_observers_loop
G12 nav_state_in_view G13 withAnimation_Fetch G14
continuousClock_missing G15 App_runs_in_tests G16 improper_state_capture
