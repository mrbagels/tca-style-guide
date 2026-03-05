# TCA Style Guide

Personal architecture style guide for iOS apps built with **The Composable Architecture (TCA)**, **SwiftUI**, and **SQLiteData**.

This repo is both a human-readable reference and an automated pipeline that generates LLM-optimized versions for use with Claude Code, Copilot, Cursor, and other AI coding tools.

## Structure

```
docs/                        → Source documentation (human-readable)
  STYLE_GUIDE.md             → Full guide (~4K lines, single source of truth)
  STYLE_GUIDE_STRIPPED.md    → Mid-level compression (~800 lines)
  STYLE_GUIDE_TINY.md        → Slim architecture spec (~120 lines)
  STYLE_GUIDE_LLM.md         → Ultra-compressed injection format (~56 lines)

examples/
  patterns/                  → Isolated pattern files with inline docs
    FeaturePattern.swift
    NavigationPattern.swift
    ViewPattern.swift
    DependencyPattern.swift
    TestingPattern.swift
    ReduceChildPattern.swift

scripts/
  build-llm-guide.py         → Build script (docs + code → LLM outputs)

skills/
  tca-style-guide/SKILL.md   → Cowork/Claude Code skill definition

dist/                        → Generated outputs (not committed, built by CI)
  FULL.md                    → Complete guide + code examples (~8K tokens)
  REFERENCE.md               → Rules + pattern summaries (~2K tokens)
  COMPACT.md                 → Essential rules only (~1K tokens)
  INJECTION.txt              → System prompt fragment (~500 tokens)
  llms.txt                   → Machine-readable index
  CLAUDE.md                  → Template for project repos
```

## How It Works

1. **Edit** the source docs in `docs/` or pattern files in `examples/patterns/`
2. **Push** to `main`
3. **GitHub Action** runs `scripts/build-llm-guide.py` to generate tiered outputs
4. **GitHub Pages** deploys the `dist/` contents + source files
5. **LLMs** discover the guide via `llms.txt` at the Pages root

## Setup

### 1. Create the GitHub Repo

```bash
cd path/to/this/folder
git init
git add .
git commit -m "Initial commit: TCA style guide project"
gh repo create tca-style-guide --public --source=. --push
```

### 2. Enable GitHub Pages

1. Go to **Settings → Pages** in the repo
2. Under **Build and deployment**, select **GitHub Actions**
3. The workflow will deploy automatically on the next push to `main`

### 3. Update URLs

After the repo is created, find-and-replace `YOUR_USERNAME` in these files:

- `dist/CLAUDE.md` (generated — will auto-update on next build)
- `skills/tca-style-guide/SKILL.md`
- `scripts/build-llm-guide.py` (the FULL.md source comment)

### 4. Use in Your Projects

**Claude Code** — Copy `dist/CLAUDE.md` into your project root as `CLAUDE.md`:

```bash
cp dist/CLAUDE.md ~/Projects/my-tca-app/CLAUDE.md
```

**Cowork** — Copy the `skills/tca-style-guide/` folder into your Cowork skills directory.

**Cursor** — Copy `dist/COMPACT.md` content into `.cursorrules`.

**Copilot** — Copy `dist/COMPACT.md` content into `.github/copilot-instructions.md`.

**Context7** — Point Context7 at the GitHub Pages URL for automatic indexing.

### 5. Local Testing

Run the build script locally to verify outputs before pushing:

```bash
python3 scripts/build-llm-guide.py
```

Outputs appear in `dist/`. These are gitignored — CI regenerates them on every push.

## Consumer Guide

| Consumer | Use This | Tokens |
|---|---|---|
| Claude Code (project CLAUDE.md) | `dist/CLAUDE.md` or `REFERENCE.md` | ~1-2K |
| Context7 / full context | `dist/FULL.md` | ~8K |
| Cursor rules | `dist/COMPACT.md` | ~1K |
| Copilot instructions | `dist/COMPACT.md` | ~1K |
| System prompt injection | `dist/INJECTION.txt` | ~500 |
| Cowork skill | `skills/tca-style-guide/SKILL.md` | on-demand |

## Contributing to the Guide

The style guide is a living document. To update:

1. Edit the source in `docs/STYLE_GUIDE.md`
2. If adding a new pattern, create a new `.swift` file in `examples/patterns/`
3. Update the compressed versions (`STRIPPED`, `TINY`, `LLM`) to reflect changes
4. Push to `main` — CI handles the rest
