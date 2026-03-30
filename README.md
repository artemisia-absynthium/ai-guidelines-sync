# claude-setup-plugin

A Claude Code plugin providing Swift/visionOS domain rules and a project-setup skill.

## What's inside

### Rules (`rules/`)

Domain-specific Claude Code rules for Swift and visionOS projects, synced into subscriber
projects via GitHub Actions. Generic workflow skills (planning, debugging, code review) are
intentionally excluded — those are covered by official Claude Code plugins.

| File | Covers |
|------|--------|
| `rules/swift/code-style.md` | Logger, file headers, import order, naming, SwiftLint |
| `rules/swift/concurrency.md` | `@MainActor`, `@Observable`, Sendable, async patterns |
| `rules/swift/testing.md` | Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`) |
| `rules/visionos/realitykit.md` | RealityView lifecycle, entity rules, z-offset, attachments |

### Skills (`skills/`)

| Skill | What it does |
|-------|-------------|
| `setup-project-ai` | Scaffolds an existing repo with the sync workflow, `shared/`/`local/` structure, and an architecture stub |

## Installation

```
/plugin install artemisia-absynthium/claude-setup-plugin
```

## Using rules in a project

Rules are not injected automatically by the plugin — they need to land as committed files
so teammates without the plugin also benefit. Each project subscribes via a GitHub Actions
workflow that syncs `rules/` into `.claude/rules/shared/` weekly.

Run `/setup-project-ai` in any existing project to install the workflow and directory structure.
New projects can be created from `apple-project-template` which includes all of this pre-wired.

## Adding `CLAUDE_RULES_PAT` to a subscriber repo

The sync workflow pushes directly to `develop` (bypassing branch protection) using a PAT:

1. GitHub → personal Settings → Developer settings → Personal access tokens → `repo` scope
2. Subscriber repo → Settings → Secrets → Actions → New secret → `CLAUDE_RULES_PAT`
