---
description: "Load the TCA/SwiftUI/SQLiteData architecture style guide for code generation, review, and refactoring. Use when writing TCA features, reducers, views, navigation, dependencies, or tests."
---

# TCA Style Guide Skill

You are now operating under a personal TCA/SwiftUI/SQLiteData architecture style guide. All code you generate, review, or refactor MUST follow these conventions.

## How to Use This Skill

1. **Read the reference guide** — Start by reading the REFERENCE.md or COMPACT.md from the deployed GitHub Pages site (or from the local `dist/` directory if available).
2. **For code generation** — Follow the patterns demonstrated in the `examples/patterns/` Swift files. Each file is self-documenting with inline `///` comments explaining the rules.
3. **For code review** — Check against the "Critical Gotchas" section (G1–G16) in the style guide.

## Quick Reference

Fetch the appropriate level of detail based on what you're doing:

- **Writing a new feature from scratch** → Read `FULL.md` (complete guide + code examples)
- **Adding to an existing feature** → Read `REFERENCE.md` (rules + pattern summaries)
- **Quick check on a convention** → Read `COMPACT.md` (essential rules only)

## Core Rules (Always Apply)

- `@Reducer struct XFeature` with `@ObservableState struct State: Equatable`
- Action: `ViewAction` (+ `BindableAction` only if bindings are used)
- Action does NOT conform to `Equatable`
- All nested action enums: `@CasePathable` + `Sendable`, alphabetized
- Dependencies declared inside `@Reducer`, never outside
- Reducer body order: `BindingReducer` → `Scope` → `Reduce` passthrough → `ReduceChild` handlers → `.ifLet`/`.forEach`
- One `ReduceChild` per action category
- `@ViewAction(for:)` macro on views, `@Bindable var store`
- Body minimal — extract sections as `private var` computed properties
- Scope stores at point of use, never pre-scope
- Never use `Binding(get:set:)` — it bypasses TCA
- Router pattern: root + path (`StackState`) + destination (`@Presents`)
- Test with `TestStore`, override deps via `withDependencies`
- Use case key path syntax for `receive` — no `Equatable` needed on Action
- Alphabetize everything: imports, enum cases, handlers, properties

## Critical Gotchas

- **G1**: Parent must never handle `child.view` or `child.internal` — only `child.delegate`
- **G2**: Missing `BindingReducer()` silently breaks all bindings
- **G3**: `.ifLet`/`.forEach` MUST come after the `Reduce` that mutates their state
- **G4**: Never mutate state inside `.run` closures — capture values, send actions back
- **G5**: Always provide cancellation IDs; missing `.cancellable(id:)` means `.cancel(id:)` does nothing
- **G6**: Avoid action ping-pong — coordinate in parent via direct state mutation
- **G10**: `Binding(get:set:)` bypasses TCA state management entirely
- **G16**: Always capture specific state values in `.run` closures: `[apiClient]`

## GitHub Pages URL

Once deployed, the style guide is available at:
`https://mrbagels.github.io/tca-style-guide/`

Update the URL above after creating the GitHub repo.
