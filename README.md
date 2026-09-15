# ai-guidelines-sync

Central source of Claude Code rules and skills for Swift, iOS, visionOS, macOS, Android, and web
projects. Rules are synced into subscriber repos automatically via GitHub Actions; `setup.sh`
scaffolds any new or existing repo in one command.

## Quick start

From the root of a repo (or from a directory containing multiple repos):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artemisia-absynthium/ai-guidelines-sync/main/setup.sh)
```

> **Note:** The `<()` form is required — it keeps `/dev/tty` open for the interactive pickers.
> `curl ... | bash` closes stdin and breaks arrow-key input.

**Single-repo mode** (run from inside a git repo): detects project type, writes config, scaffolds sync workflow, pre-populates rules and skills from upstream.

**Multi-repo mode** (run from a directory of repos): presents an interactive multi-select picker, then runs single-repo setup on each selected repo.

### Requirements

- macOS with Homebrew installed (`https://brew.sh/`)
- `jq` — installed automatically if absent, removed when the script exits (requires Homebrew)

---

## What the script does

1. **Checks out the default branch and pulls** — re-reads the remote's default branch first (a clone's cached `origin/HEAD` goes stale when the default changes on GitHub), then ensures setup runs on the latest remote state. Skipped gracefully when the repo has no commits or no upstream tracking branch. A dirty tree that is already up to date proceeds; a clone that is behind its remote and cannot be fast-forwarded stops setup for that repo (in multi-repo mode it is listed under "Failed" at the end, as is any repo where a later step could not write a file).
2. **Detects project type** — infers rule categories from `.xcodeproj`, `Package.swift`, `build.gradle`, `package.json`, `playwright.config.*`, `pyproject.toml`
3. **Writes `.claude/rules-sync.txt`** — category config; skip if already exists (preserving user edits)
4. **Writes `.github/workflows/sync-claude-rules.yml`** — thin wrapper calling the composite action; always overwritten; sync day is chosen interactively
5. **Pre-populates rules and skills** from a single tarball of the upstream repo — one download, outside the GitHub API rate limit, byte-identical to what the Action syncs (so teammates get them immediately on next clone)
6. **Writes the guard hook** to `.claude/settings.json` — blocks accidental edits to sync-managed files. A settings.json the script cannot read (not valid JSON, or `hooks` not in the shape Claude Code reads) is primed rather than refused: readable parts are kept, unreadable parts dropped, the original is copied to `settings.json.before-priming`, and a warning says so — review the result with `git diff`, delete the backup before committing; keys from the old shape may remain
7. **Migration** — renames `.claude/rules-sync` → `.claude/rules-sync.txt`, removes the retired `setup-project-ai` skill, cleans stale category directories

Re-running the script is the update command — `rules-sync.txt` is preserved, everything else is refreshed. In multi-repo mode, per-repo failures are collected and printed as a summary at the end rather than aborting the run.

---

## How sync works

Subscriber repos run a thin workflow that calls the composite action:

```yaml
# .github/workflows/sync-claude-rules.yml — written by setup.sh, never needs manual changes
on:
  schedule:
    - cron: '0 9 * * 1'   # chosen at setup time
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          ssh-key: ${{ secrets.CLAUDE_RULES_DEPLOY_KEY }}
      - uses: artemisia-absynthium/ai-guidelines-sync/.github/actions/sync@main
```

The composite action at `.github/actions/sync/action.yml` in **this repo** contains all sync logic.
When sync logic changes, only this repo is updated — subscriber workflow files never change.

### What the action does

1. Checks out this repo alongside the subscriber workspace
2. Detects project type and auto-adds new categories to `rules-sync.txt` (skips commented-out ones — those are explicit exclusions)
3. Deletes `synced/<category>/` directories for removed categories
4. `rsync --delete` each active category from upstream into `.claude/rules/synced/<category>/`
5. Syncs skills using a manifest (`.claude/skills/.synced-manifest`) to safely remove skills deleted upstream without touching local project skills
6. Commits and pushes via the deploy key

### Ownership & deletion contract

The sync is a reconciliation loop, not a script: every run must converge any subscriber
state (including a half-failed previous run) to the table below. Each managed path has an
explicit owner, and the owner determines what an upstream deletion does to subscribers.
**No path may be added to the sync without adding its row here first** — a path without a
deletion story is a distribution mechanism without an ownership model, and the first
revert is when you find out.

| Managed path (subscriber) | Owner | What a sync does | When upstream deletes it |
|---|---|---|---|
| `.claude/rules/synced/<cat>/` | Upstream | `rsync --delete` — the directory becomes exactly the upstream category | File (or whole category) disappears from every subscriber on its next sync |
| `.claude/skills/<name>/` | Mixed — upstream and local skills share the directory | rsync without `--delete`; the manifest records which names are upstream-owned | Deleted only if the manifest lists it; a local skill with the same name created *after* the manifest dropped it is invisible to the sync forever |
| `.claude/rules-sync.txt` | Subscriber (upstream appends detected categories) | Merge: auto-detected categories appended, commented lines respected as exclusions | n/a — never deleted by the sync |
| `.claude/settings.json` | Subscriber | `setup.sh` only: the script owns exactly one `PreToolUse` entry whose command matches `rules/synced` (replaced on re-run); everything else is merged around. An unusable file is primed — kept: every readable part; dropped with a warning: a non-object root or `hooks`, a non-array `PreToolUse`, and `PreToolUse` entries that are not objects or whose `hooks`/`command` have the wrong type; the original is copied to `settings.json.before-priming` (never overwritten: an existing backup is a hard stop). A symlink at the file or at a sidecar name, a directory, or an unwritable file is a hard stop | n/a — never touched by the Action |
| Hook directories (Action) | — | No hook-directory step exists in the Action at present; if one returns, its contract must be stated here first (previous incarnation: skip-when-source-absent, `rsync --delete` when present) | — |

Consequence worth knowing when working *with* the grain of this contract: removing a skill
upstream and re-creating it locally in a subscriber (after one sync run) permanently hands
that skill to the subscriber — the manifest no longer tracks the name, so later syncs never
touch it. This is the sanctioned way to fork a skill for a local pilot; it reverses
automatically when the skill is re-added upstream and a sync re-adopts the name into the
manifest.

---

## Selective sync — `.claude/rules-sync.txt`

Controls which rule categories a subscriber repo receives. One category per line. Comment out a line to explicitly exclude it (it won't be re-added automatically):

```
# Category names match directories under rules/ in ai-guidelines-sync.
# Comment out a line to exclude that category from auto-detection.
swift
ios
visionos
xcode
# mac   ← explicitly excluded; auto-detection won't add it back
```

**Available categories**: `swift`, `ios`, `mac`, `visionos`, `xcode`, `android`, `web`, `database`

The `workflow` category is always synced — do not add it to `rules-sync.txt`.

---

## Rules

| Category | Sync | Covers |
|----------|------|--------|
| `workflow` | always | How work is planned, built, tested, documented and contributed — charter, plan execution, build and docs discipline, falsifiable assertions, decisions-not-code-state docs, terminology, tool fallback, pull-first, UI states, `TECH-DEBT`, upstream contribution |
| `swift` | opt-in | The language and Apple frameworks on any Swift target — concurrency, SwiftUI, Swift Testing, Core Data, dates, assets, archive security, logging and file layout |
| `ios` | opt-in | iOS-only surfaces — UIKit asset loading, Liquid Glass |
| `mac` | opt-in | macOS-only affordances — menus, keyboard shortcuts, windows, native chrome |
| `visionos` | opt-in | RealityKit — RealityView lifecycle, entity rules, attachments |
| `xcode` | opt-in | Toolchain and project — Xcode MCP usage, SPM only, schemes, test destinations, run verification from the xcresult, UI-test isolation and portability, zero warnings |
| `android` | opt-in | Kotlin — code style, Compose state and lifecycle, Room, JUnit/Robolectric/MockK/Turbine testing |
| `web` | opt-in | Playwright — test execution vs visual verification |
| `database` | opt-in | Schema and transaction rules independent of the ORM — partial unique indexes |

Each file's title states its rule — browse `rules/<category>/` for the catalog. This table stops
at categories on purpose: a per-file list is the directory listing copied by hand, and it drifts
(`rules/workflow/docs-record-decisions.md`).
---

## Skills

| Skill | What it does |
|-------|-------------|
| `design-review-lens` | Full design-review checklist (SOLID, Clean Architecture, GRASP, Clean Code, coupling laws, guardrails) for reviewing a diff or branch |
| `lift-to-shared-rules` | Generalizes a pattern found in a project and proposes it upstream — commits locally, pushes or opens the PR only on an explicit go |
| `swift-concurrency-review` | Dedicated Swift concurrency review pass — reentrancy, continuations, cancellation, ordering, `@unchecked Sendable` |
| `planning-discipline` | Type-level design, invariant-first planning, named precedents, and complexity budgets — invoked at plan time |

After the first sync workflow run, skills are committed to `.claude/skills/<name>/` in each subscriber repo — available to all teammates automatically.

---

## Adding a deploy key to a subscriber repo

The sync workflow pushes directly to the default branch, bypassing branch protection, via a deploy key:

1. `ssh-keygen -t ed25519 -C "claude-rules-sync" -f /tmp/claude_rules_deploy_key -N ""`
2. Copy public key: `cat /tmp/claude_rules_deploy_key.pub | pbcopy`  
   Subscriber repo → Settings → Deploy keys → Add → paste → enable **Allow write access**
3. If the default branch has protection rules:  
   Settings → Branches → edit rule → add the deploy key to the bypass list
4. Copy private key: `cat /tmp/claude_rules_deploy_key | pbcopy`  
   Subscriber repo → Settings → Secrets → Actions → `CLAUDE_RULES_DEPLOY_KEY` → paste
5. `rm /tmp/claude_rules_deploy_key*`
6. Trigger the workflow manually once: Actions → Sync Claude Rules and Skills → Run workflow

---

## Contributing rules

Use the `lift-to-shared-rules` skill inside any Claude Code session to generalize a pattern and
propose it upstream. The skill handles anonymization, coherence checks, and the commit/PR flow.

To run the test suite:

```bash
bats tests/
```

Requires [BATS](https://github.com/bats-core/bats-core): `brew install bats-core`.
