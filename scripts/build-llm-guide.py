#!/usr/bin/env python3
"""
Build script for the TCA Style Guide project.

Reads human-readable docs (.md) and annotated Swift pattern files (.swift),
then generates LLM-optimized output at multiple token budgets:

  - dist/FULL.md          — complete guide with all code examples
  - dist/REFERENCE.md     — rules + compressed examples
  - dist/COMPACT.md       — essential rules only
  - dist/INJECTION.txt    — single-shot system prompt fragment
  - dist/llms.txt         — machine-readable index for LLM discovery
  - dist/CLAUDE.md        — template for project repos
  - dist/topic-*.md       — per-topic guides (core patterns always included)

Pattern files use `/// @topic <name>` to declare their category.
Files tagged `@topic core` are included in EVERY topic-specific output.

Usage:
    python3 scripts/build-llm-guide.py
"""

import os
import re
import glob
import textwrap
from collections import defaultdict
from pathlib import Path
from datetime import datetime, timezone

## ─── Configuration ─────────────────────────────────────────────────────────

ROOT = Path(__file__).resolve().parent.parent
DOCS_DIR = ROOT / "docs"
PATTERNS_DIR = ROOT / "examples" / "patterns"
DIST_DIR = ROOT / "dist"

## The main style guide is the single source of truth
MAIN_GUIDE = DOCS_DIR / "STYLE_GUIDE.md"

## ─── Helpers ───────────────────────────────────────────────────────────────

def read_file(path: Path) -> str:
    """Read a file and return its contents, or empty string if missing."""
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"  ⚠ Missing: {path}")
        return ""


def extract_swift_docs(swift_content: str) -> dict:
    """
    Extract structured documentation from a Swift pattern file.

    Returns a dict with:
      - title: the pattern name from the `# Title` doc comment
      - topic: the `@topic` tag value (e.g., "core", "navigation")
      - summary: the description block
      - rules: list of key rules
      - code: the full Swift source (for FULL output)
    """
    lines = swift_content.split("\n")

    title = ""
    topic = ""
    summary_lines = []
    rules = []
    in_header = True

    for line in lines:
        stripped = line.strip()

        ## Extract title from `/// # Title` comments
        if stripped.startswith("/// # "):
            title = stripped.replace("/// # ", "")
            continue

        ## Extract topic from `/// @topic <name>` comments
        if stripped.startswith("/// @topic "):
            topic = stripped.replace("/// @topic ", "").strip()
            continue

        ## Extract summary lines (/// comments before code)
        if in_header and stripped.startswith("///"):
            content = stripped[3:].strip()
            if content.startswith("- "):
                rules.append(content[2:])
            elif content and not content.startswith("#") and not content.startswith("@"):
                summary_lines.append(content)
            continue

        ## Once we hit non-doc-comment code, header is done
        if in_header and not stripped.startswith("///") and stripped:
            if stripped != "":
                in_header = False

    return {
        "title": title,
        "topic": topic,
        "summary": " ".join(summary_lines),
        "rules": rules,
        "code": swift_content,
    }


def collect_patterns() -> list[dict]:
    """Collect all Swift pattern files and extract their documentation."""
    patterns = []
    pattern_files = sorted(glob.glob(str(PATTERNS_DIR / "*.swift")))

    for filepath in pattern_files:
        content = read_file(Path(filepath))
        if not content:
            continue
        doc = extract_swift_docs(content)
        doc["filename"] = os.path.basename(filepath)
        patterns.append(doc)

    return patterns


def group_by_topic(patterns: list[dict]) -> dict[str, list[dict]]:
    """
    Group patterns by their @topic tag.

    Returns a dict like:
      {"core": [...], "navigation": [...], "view": [...], ...}

    Patterns without a topic are placed under "uncategorized".
    """
    groups = defaultdict(list)
    for pattern in patterns:
        topic = pattern.get("topic") or "uncategorized"
        groups[topic].append(pattern)
    return dict(groups)


def build_timestamp() -> str:
    """ISO 8601 UTC timestamp for build metadata."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


## ─── Output Generators ────────────────────────────────────────────────────

def build_full(main_guide: str, patterns: list[dict]) -> str:
    """
    FULL.md — Complete guide with embedded Swift examples.
    Suitable for project-level CLAUDE.md or Context7 indexing
    where token budget is generous.
    """
    sections = []
    sections.append("# TCA / SwiftUI / SQLiteData Style Guide\n")
    sections.append(f"<!-- Generated: {build_timestamp()} -->\n")
    sections.append("<!-- Source: https://github.com/mrbagels/tca-style-guide -->\n\n")

    ## Include the stripped guide as the prose foundation
    stripped = read_file(DOCS_DIR / "STYLE_GUIDE_STRIPPED.md")
    if stripped:
        sections.append(stripped)
    else:
        ## Fallback: use main guide (will be large)
        sections.append(main_guide)

    ## Append pattern code examples grouped by topic
    topic_groups = group_by_topic(patterns)
    sections.append("\n\n---\n\n# Code Examples\n\n")
    sections.append("The following Swift files demonstrate each pattern with inline documentation.\n\n")

    ## Emit core patterns first, then others alphabetically
    ordered_topics = ["core"] + sorted(t for t in topic_groups if t != "core")

    for topic in ordered_topics:
        if topic not in topic_groups:
            continue
        topic_label = topic.replace("-", " ").title()
        sections.append(f"### Topic: {topic_label}\n\n")
        for pattern in topic_groups[topic]:
            sections.append(f"## {pattern['title']}\n\n")
            sections.append(f"**File:** `examples/patterns/{pattern['filename']}`  \n")
            sections.append(f"**Topic:** `{topic}`\n\n")
            sections.append("```swift\n")
            sections.append(pattern["code"])
            sections.append("\n```\n\n")

    return "".join(sections)


def build_reference(patterns: list[dict]) -> str:
    """
    REFERENCE.md — Rules with compressed code snippets.
    Good for Claude Code CLAUDE.md files in individual project repos.
    """
    sections = []
    sections.append("# TCA Style Guide — Reference\n\n")
    sections.append(f"<!-- Generated: {build_timestamp()} -->\n\n")

    ## Use the tiny guide as the rules foundation
    tiny = read_file(DOCS_DIR / "STYLE_GUIDE_TINY.md")
    if tiny:
        sections.append(tiny)

    ## Add compressed pattern summaries grouped by topic
    sections.append("\n\n---\n\n## Pattern Quick Reference\n\n")

    topic_groups = group_by_topic(patterns)
    ordered_topics = ["core"] + sorted(t for t in topic_groups if t != "core")

    for topic in ordered_topics:
        if topic not in topic_groups:
            continue
        topic_label = topic.replace("-", " ").title()
        sections.append(f"#### {topic_label}\n\n")
        for pattern in topic_groups[topic]:
            sections.append(f"**{pattern['title']}** — {pattern['summary'][:120]}\n")
            if pattern["rules"]:
                for rule in pattern["rules"]:
                    sections.append(f"- {rule}\n")
            sections.append("\n")

    return "".join(sections)


def build_compact() -> str:
    """
    COMPACT.md — Essential rules only, no code.
    For token-constrained contexts like Copilot custom instructions or Cursor rules.
    """
    sections = []
    sections.append("# TCA Architecture Rules (Compact)\n\n")
    sections.append(f"<!-- Generated: {build_timestamp()} -->\n\n")

    tiny = read_file(DOCS_DIR / "STYLE_GUIDE_TINY.md")
    if tiny:
        sections.append(tiny)
    else:
        sections.append("*Error: STYLE_GUIDE_TINY.md not found.*\n")

    return "".join(sections)


def build_injection() -> str:
    """
    INJECTION.txt — Ultra-compressed single-shot prompt fragment.
    For system prompt injection where every token counts.
    """
    sections = []
    sections.append(f"# Generated: {build_timestamp()}\n")

    llm = read_file(DOCS_DIR / "STYLE_GUIDE_LLM.md")
    if llm:
        sections.append(llm)
    else:
        sections.append("*Error: STYLE_GUIDE_LLM.md not found.*\n")

    return "".join(sections)


def build_topic_guides(patterns: list[dict]) -> dict[str, str]:
    """
    Generate per-topic guide files.

    Each topic guide includes:
      1. All `core` patterns (always included — ReduceChild, Feature Pattern)
      2. All patterns matching that specific topic
      3. Rules summary for the included patterns

    Returns a dict of filename → content, e.g.:
      {"topic-navigation.md": "...", "topic-testing.md": "..."}

    Skips generating a standalone file for `core` since core patterns
    are embedded in every other topic output.
    """
    topic_groups = group_by_topic(patterns)
    core_patterns = topic_groups.get("core", [])

    ## Only generate topic files for non-core, non-uncategorized topics
    topic_files = {}
    for topic, topic_patterns in sorted(topic_groups.items()):
        if topic in ("core", "uncategorized"):
            continue

        topic_label = topic.replace("-", " ").title()
        sections = []
        sections.append(f"# TCA Style Guide — {topic_label}\n\n")
        sections.append(f"<!-- Generated: {build_timestamp()} -->\n")
        sections.append(f"<!-- Topic: {topic} -->\n\n")
        sections.append(f"This guide covers **{topic_label}** patterns along with ")
        sections.append("the core patterns (Feature, ReduceChild) that are always relevant.\n\n")

        ## Core patterns first
        if core_patterns:
            sections.append("---\n\n## Core Patterns (Always Applicable)\n\n")
            for pattern in core_patterns:
                sections.append(f"### {pattern['title']}\n\n")
                sections.append(f"**File:** `examples/patterns/{pattern['filename']}`\n\n")
                if pattern["rules"]:
                    sections.append("**Rules:**\n")
                    for rule in pattern["rules"]:
                        sections.append(f"- {rule}\n")
                    sections.append("\n")
                sections.append("```swift\n")
                sections.append(pattern["code"])
                sections.append("\n```\n\n")

        ## Topic-specific patterns
        sections.append(f"---\n\n## {topic_label} Patterns\n\n")
        for pattern in topic_patterns:
            sections.append(f"### {pattern['title']}\n\n")
            sections.append(f"**File:** `examples/patterns/{pattern['filename']}`\n\n")
            if pattern["summary"]:
                sections.append(f"{pattern['summary']}\n\n")
            if pattern["rules"]:
                sections.append("**Rules:**\n")
                for rule in pattern["rules"]:
                    sections.append(f"- {rule}\n")
                sections.append("\n")
            sections.append("```swift\n")
            sections.append(pattern["code"])
            sections.append("\n```\n\n")

        filename = f"topic-{topic}.md"
        topic_files[filename] = "".join(sections)

    return topic_files


def build_llms_txt(patterns: list[dict], topic_files: dict[str, str]) -> str:
    """
    llms.txt — Machine-readable index following the llms.txt convention.
    This file tells LLMs what documentation is available and where to find it.
    Deployed to the root of GitHub Pages.
    """
    lines = []
    lines.append("# TCA / SwiftUI / SQLiteData Style Guide\n")
    lines.append("\n")
    lines.append("> Personal architecture style guide for iOS apps built with ")
    lines.append("The Composable Architecture (TCA), SwiftUI, and SQLiteData.\n")
    lines.append("\n")
    lines.append("## Docs\n")
    lines.append("\n")
    lines.append("- [Full Guide (with code examples)](FULL.md): "
                 "Complete style guide with embedded Swift pattern examples.\n")
    lines.append("- [Reference Guide](REFERENCE.md): "
                 "Rules with compressed pattern summaries.\n")
    lines.append("- [Compact Rules](COMPACT.md): "
                 "Essential architecture rules only.\n")
    lines.append("- [Injection Fragment](INJECTION.txt): "
                 "Ultra-compressed prompt fragment.\n")

    ## Topic-specific guides
    if topic_files:
        lines.append("\n")
        lines.append("## Topic Guides\n")
        lines.append("\n")
        lines.append("Focused guides that include only relevant patterns plus core patterns.\n")
        lines.append("\n")
        for filename in sorted(topic_files.keys()):
            ## Extract topic name from filename
            topic = filename.replace("topic-", "").replace(".md", "")
            topic_label = topic.replace("-", " ").title()
            lines.append(f"- [{topic_label} Patterns]({filename}): "
                         f"Core + {topic_label} patterns with full code.\n")

    lines.append("\n")
    lines.append("## Code Examples\n")
    lines.append("\n")

    topic_groups = group_by_topic(patterns)
    ordered_topics = ["core"] + sorted(t for t in topic_groups if t != "core")

    for topic in ordered_topics:
        if topic not in topic_groups:
            continue
        topic_label = topic.replace("-", " ").title()
        for pattern in topic_groups[topic]:
            lines.append(
                f"- [{pattern['title']}](../examples/patterns/{pattern['filename']}) "
                f"[{topic}]: "
                f"{pattern['summary'][:80]}{'...' if len(pattern['summary']) > 80 else ''}\n"
            )

    lines.append("\n")
    lines.append("## Optional\n")
    lines.append("\n")
    lines.append("- [Source Style Guide](../docs/STYLE_GUIDE.md): "
                 "Full human-readable source document (~4K lines).\n")

    return "".join(lines)


def build_claude_md() -> str:
    """
    Generate a CLAUDE.md template that projects can copy into their repos.
    This tells Claude Code about the style guide conventions.
    """
    sections = []
    sections.append("# CLAUDE.md — TCA Style Guide Instructions\n\n")
    sections.append("## Architecture\n\n")
    sections.append("This project follows a personal TCA/SwiftUI/SQLiteData style guide.\n")
    sections.append("The full reference is maintained at: ")
    sections.append("https://mrbagels.github.io/tca-style-guide/\n\n")
    sections.append("## Quick Rules\n\n")

    tiny = read_file(DOCS_DIR / "STYLE_GUIDE_TINY.md")
    if tiny:
        ## Strip the title since we have our own header
        lines = tiny.split("\n")
        content_lines = []
        skip_first_header = True
        for line in lines:
            if skip_first_header and line.startswith("# "):
                skip_first_header = False
                continue
            content_lines.append(line)
        sections.append("\n".join(content_lines))

    sections.append("\n\n## Code Examples\n\n")
    sections.append("For detailed pattern examples with inline documentation, see:\n")
    sections.append("https://mrbagels.github.io/tca-style-guide/FULL.md\n")

    return "".join(sections)


## ─── Main Build ────────────────────────────────────────────────────────────

def main():
    print("🔨 Building TCA Style Guide LLM outputs...\n")

    ## Ensure dist directory exists
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    ## Read source material
    print("📖 Reading source docs...")
    main_guide = read_file(MAIN_GUIDE)
    if not main_guide:
        print("  ❌ STYLE_GUIDE.md is required but missing!")
        return 1

    ## Collect pattern files
    print("📦 Collecting pattern files...")
    patterns = collect_patterns()
    print(f"  Found {len(patterns)} pattern files")

    ## Show topic breakdown
    topic_groups = group_by_topic(patterns)
    for topic, group in sorted(topic_groups.items()):
        filenames = ", ".join(p["filename"] for p in group)
        print(f"    [{topic}] {filenames}")

    ## Generate topic-specific guides
    print("\n📂 Generating topic guides...")
    topic_files = build_topic_guides(patterns)
    for filename in sorted(topic_files.keys()):
        print(f"    • {filename}")

    ## Generate outputs
    print("\n⚡ Generating outputs...")

    outputs = {
        "FULL.md": build_full(main_guide, patterns),
        "REFERENCE.md": build_reference(patterns),
        "COMPACT.md": build_compact(),
        "INJECTION.txt": build_injection(),
        "llms.txt": build_llms_txt(patterns, topic_files),
        "CLAUDE.md": build_claude_md(),
    }

    ## Add topic files to outputs
    outputs.update(topic_files)

    for filename, content in sorted(outputs.items()):
        output_path = DIST_DIR / filename
        output_path.write_text(content, encoding="utf-8")

        ## Rough token estimate (1 token ≈ 4 chars for English)
        token_estimate = len(content) // 4
        print(f"  ✅ {filename:25s} {len(content):>8,} chars  (~{token_estimate:,} tokens)")

    print(f"\n✨ Build complete! Outputs in {DIST_DIR.relative_to(ROOT)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
