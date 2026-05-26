# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this repo is

Central source of Claude Code rules and skills for Swift, iOS, visionOS, macOS, Android, and web
projects. Rules are synced into subscriber repos via GitHub Actions. `setup.sh` scaffolds any repo.

## Build and test

```bash
bats tests/        # unit tests for setup.sh (requires: brew install bats-core)
```

No other build step or package manager.

## Shell scripting constraints

`setup.sh` targets bash 3.2 (macOS system bash). Active constraints:
- `set -uo pipefail` — **no** `set -e`
- Empty array + `set -u`: `"${arr[@]}"` aborts in bash 3.2 when the array is empty.
  Use `${arr[@]+"${arr[@]}"}` (established codebase pattern, see commit `f0f3fbc`)
- Guard early returns: `|| return 0` not `|| return` when absence means success
- BATS: a non-zero exit from a test body silently drops that test (shows as count
  mismatch `Executed N-1 instead of N`, not as `not ok`)

## Architecture

### Two-layer sync

| Layer | What it does | Mechanism |
|---|---|---|
| Project setup | Scaffold dirs, write rules-sync.txt, write thin workflow, pre-populate rules/skills, write guard hook | `setup.sh` (curl-runnable bash script) |
| Ongoing sync | Pull latest rules/skills from upstream, auto-detect new categories, cleanup stale, commit | Composite action at `.github/actions/sync/action.yml` |

The skill layer is kept for tasks that require reasoning:

| Skill | Purpose |
|---|---|
| `lift-to-shared-rules` | Generalize a pattern and propose it upstream |

### Rules (`rules/`)

Source of truth — never edit inside a subscriber's `.claude/rules/synced/`.

**Available categories**: `swift`, `ios`, `mac`, `visionos`, `xcode`, `android`, `web`, `workflow`  
**Future (detection only, no rules yet)**: `python`, `node`

The `workflow` category is always synced to every subscriber regardless of `rules-sync.txt`.

### Composite action (`.github/actions/sync/action.yml`)

All sync logic lives here. Subscriber workflow files are thin wrappers pointing at `@main` — they
never need updating. To change sync logic, commit here.

### Subscriber category config (`.claude/rules-sync.txt`)

One category per line. Comment out a line to explicitly exclude it — it won't be re-added by
auto-detection. The action auto-adds newly detected categories on the next sync unless commented out.

### Design invariant

Rules sync writes only to `.claude/rules/synced/` — a managed directory. Skills sync writes to
`.claude/skills/<name>/` alongside local project skills; the manifest tracks upstream removals
without touching local skills.

## Lifting rules cross-project

Use the `lift-to-shared-rules` skill. It reads the local clone path from `CLAUDE_SETUP_PATH`
(set in `~/.zshenv`). Teammates without push access get a fork/PR flow automatically.
