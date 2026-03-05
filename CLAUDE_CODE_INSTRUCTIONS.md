# Claude Code Instructions: TCA Style Guide Project

This file contains everything needed to finish building and deploy this project.
Read this file in full before starting any work.

---

## Project Context

This is a **living style guide** for iOS apps built with The Composable Architecture (TCA), SwiftUI, and SQLiteData. The repo serves two purposes:

1. **Human-readable source** — docs and annotated Swift files that developers read directly
2. **LLM-optimized outputs** — generated automatically via CI and deployed to GitHub Pages

The pipeline is: edit source → push to main → GitHub Action builds tiered outputs → GitHub Pages hosts them → LLMs discover via `llms.txt`.

### What Already Exists

**Fully built and working:**
- `docs/` — Four tiers of documentation (STYLE_GUIDE.md, STRIPPED, TINY, LLM)
- `examples/patterns/` — 8 annotated Swift pattern files with `@topic` tags
- `scripts/build-llm-guide.py` — Build script that generates 11 output files (6 standard + 5 topic-specific)
- `.github/workflows/deploy.yml` — GitHub Action for build + deploy
- `skills/tca-style-guide/SKILL.md` — Cowork/Claude Code skill
- `README.md`, `.gitignore`
- `dist/` — Generated outputs (gitignored, rebuilt by CI)

**Scaffolded but empty:**
- `examples/reference-app/` — Has directory structure (Sources/Features, Sources/Dependencies, Sources/Models, Tests/) but no Swift files

---

## Task 1: Build the Reference App

### Purpose

The reference app is a small but complete TCA app that demonstrates every pattern from the style guide working together. It is NOT a runnable Xcode project — it's a set of Swift source files that serve as a connected example. Think of it as "the patterns, but wired into a real feature graph."

### Architecture

The app should be a simple **Items** app (task list, notes, inventory — pick whatever domain keeps the code clear). It must demonstrate:

1. **AppRouter** — TabView with 2 tabs (Items, Settings), deep link handling, global modals
2. **ItemsRouter** — NavigationStack with list → detail → edit push navigation
3. **ItemsListFeature** — List feature using ReduceChild for action splitting
4. **ItemDetailFeature** — Detail view with edit/delete actions, child presentation
5. **ItemEditorFeature** — Form editing with validation, optimistic save, cancellation
6. **SettingsFeature** — Simple feature demonstrating bindings and dependency usage
7. **ItemClient** — Dependency client (struct with closures) with live/test/preview values
8. **Item model** — Simple Equatable/Identifiable struct

### File Placement

```
examples/reference-app/
  Sources/
    App/
      ReferenceApp.swift         → @main entry point with _XCTIsTesting guard
      AppRouter.swift            → Root coordinator: tabs, deep links, global modals
      AppRouterView.swift        → TabView + modal overlays
    Features/
      Items/
        ItemsRouter.swift        → StackState + Destination for items flow
        ItemsRouterView.swift    → NavigationStack view
        ItemsListFeature.swift   → List reducer with ReduceChild
        ItemsListView.swift      → List view with @ViewAction
        ItemDetailFeature.swift  → Detail reducer with child presentation
        ItemDetailView.swift     → Detail view
        ItemEditorFeature.swift  → Form editing, validation, optimistic updates
        ItemEditorView.swift     → Form view with inline validation errors
      Settings/
        SettingsFeature.swift    → Bindings, @AppStorage-like patterns
        SettingsView.swift       → Settings form
    Dependencies/
      ItemClient.swift           → DependencyKey client with live/test/preview
    Models/
      Item.swift                 → Domain model
  Tests/
    ItemsListFeatureTests.swift  → TestStore tests for list feature
    ItemEditorFeatureTests.swift → TestStore tests for editor (validation, save, cancel)
    AppRouterTests.swift         → Deep link and tab coordination tests
```

### Critical Style Rules to Follow

Read `docs/STYLE_GUIDE.md` and ALL pattern files in `examples/patterns/` before writing any code. Every file in the reference app must follow these conventions:

- `@Reducer` struct, `@ObservableState` on State, `ViewAction` on Action
- Actions organized: `ViewAction` (view), `InternalAction` (internal), `DelegateAction` (delegate), destination/path enums
- Reducer body order: `BindingReducer` → `Reduce` (core) → `ReduceChild` blocks → `.forEach`/`.ifLet`
- Child delegation via `Reduce` that switches on `.presented`/path actions, ONLY handles `.delegate`
- `@Dependency` declared inside reducer struct, never in State or View
- Views use `@ViewAction(for:)` macro, never `store.send()` directly
- `@Bindable var store` for binding support
- Scope stores at point of use in views, never pass pre-scoped stores
- `CancelID` enum for typed cancellation
- `_XCTIsTesting` guard in app entry point
- Alphabetize: imports, action cases, state properties, handlers
- Every file gets inline `///` documentation explaining what it demonstrates

### What NOT to Include

- No Package.swift or Xcode project files — this is documentation, not a buildable target
- No actual persistence layer — ItemClient.liveValue can use in-memory storage
- No third-party dependencies beyond ComposableArchitecture
- No complex UI — keep views simple, the architecture is the point

### Inline Documentation Style

Every file should have a header doc comment explaining what pattern it demonstrates, like the pattern files do. Example:

```swift
/// # Items List Feature
/// @topic core
///
/// Demonstrates a list feature using ReduceChild to split action handling
/// into focused handler properties. Shows: loading, deletion, refresh,
/// and child delegation from the router.
```

---

## Task 2: Deploy to GitHub

### Initialize and Push

```bash
cd /path/to/styleguide
git init
git add .
git commit -m "Initial commit: TCA style guide with patterns, build pipeline, and reference app"
gh repo create tca-style-guide --public --source=. --push
```

### Enable GitHub Pages

After creating the repo:

1. Go to **Settings → Pages**
2. Under **Build and deployment**, select **GitHub Actions**
3. The deploy workflow triggers automatically on push to main

### Update Placeholder URLs

Find and replace `YOUR_USERNAME` with the actual GitHub username in:

- `scripts/build-llm-guide.py` (line in `build_full()` source comment)
- `skills/tca-style-guide/SKILL.md` (GitHub Pages URL reference)
- `README.md` (if any leftover references)

The generated files (`dist/CLAUDE.md`, `dist/llms.txt`, etc.) will pick up the change on the next build since the build script embeds the URL.

### Verify Deployment

After the Action runs:

1. Check the Actions tab — the "Deploy Style Guide" workflow should show green
2. Visit `https://YOUR_USERNAME.github.io/tca-style-guide/` — should redirect to llms.txt
3. Visit `https://YOUR_USERNAME.github.io/tca-style-guide/llms.txt` — should list all docs and topic guides
4. Visit `https://YOUR_USERNAME.github.io/tca-style-guide/FULL.md` — should have the complete guide with code
5. Visit `https://YOUR_USERNAME.github.io/tca-style-guide/topic-navigation.md` — should have core + navigation patterns

---

## Task 3: Post-Deploy Integration

### Claude Code (per-project)

Copy the generated CLAUDE.md into each TCA project:

```bash
curl -o CLAUDE.md https://YOUR_USERNAME.github.io/tca-style-guide/CLAUDE.md
```

Or for the full guide with code examples:

```bash
curl -o CLAUDE.md https://YOUR_USERNAME.github.io/tca-style-guide/REFERENCE.md
```

### Context7

Context7 should automatically discover and index the repo if it's public. The `llms.txt` at the Pages root follows the convention Context7 uses for discovery.

### Cursor / Copilot

Copy `dist/COMPACT.md` contents into `.cursorrules` or `.github/copilot-instructions.md` respectively.

---

## Build Script Reference

The build script (`scripts/build-llm-guide.py`) generates these outputs:

| File | Contents | Use Case |
|---|---|---|
| `FULL.md` | Docs + all pattern code | Context7, full context windows |
| `REFERENCE.md` | Rules + pattern summaries | Project CLAUDE.md files |
| `COMPACT.md` | Rules only, no code | Cursor/Copilot rules |
| `INJECTION.txt` | Ultra-compressed fragment | System prompt injection |
| `llms.txt` | Machine-readable index | LLM discovery |
| `CLAUDE.md` | Template for project repos | Claude Code |
| `topic-*.md` | Core + topic patterns | Focused context for specific tasks |

**Topic system:** Each `.swift` pattern file has a `/// @topic <name>` tag. Files tagged `@topic core` (FeaturePattern, ReduceChildPattern) are included in EVERY topic output. Topic guides are generated for: architecture, dependency, navigation, testing, view.

Run locally:

```bash
python3 scripts/build-llm-guide.py
```

---

## File Inventory

### Pattern Files (examples/patterns/)

| File | Topic | What It Demonstrates |
|---|---|---|
| `FeaturePattern.swift` | core | Canonical 4-part feature layout |
| `ReduceChildPattern.swift` | core | ReduceChild/ReduceChildWithState, lifecycle hooks |
| `NavigationPattern.swift` | navigation | Single-level router (list → detail → edit) |
| `AppRouterPattern.swift` | navigation | App-level coordinator: tabs, deep links, global modals |
| `ViewPattern.swift` | view | View conventions, @ViewAction, focus, scoping |
| `DependencyPattern.swift` | dependency | Client pattern, DependencyKey, live/test/preview |
| `TestingPattern.swift` | testing | TestStore, exhaustive assertions, clock |
| `CompleteFeaturePattern.swift` | architecture | Production-grade feature: forms, validation, optimistic updates |

### Documentation Files (docs/)

| File | Size | Purpose |
|---|---|---|
| `STYLE_GUIDE.md` | ~4K lines | Single source of truth, human-readable |
| `STYLE_GUIDE_STRIPPED.md` | ~800 lines | Mid-level compression for FULL output |
| `STYLE_GUIDE_TINY.md` | ~120 lines | Slim rules for REFERENCE/COMPACT |
| `STYLE_GUIDE_LLM.md` | ~56 lines | Ultra-compressed for INJECTION |
