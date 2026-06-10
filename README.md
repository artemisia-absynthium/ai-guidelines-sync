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

1. **Checks out the default branch and pulls** — ensures setup runs on the latest remote state. Skipped gracefully when the repo has no commits or no upstream tracking branch.
2. **Detects project type** — infers rule categories from `.xcodeproj`, `Package.swift`, `build.gradle`, `package.json`, `playwright.config.*`, `pyproject.toml`
3. **Writes `.claude/rules-sync.txt`** — category config; skip if already exists (preserving user edits)
4. **Writes `.github/workflows/sync-claude-rules.yml`** — thin wrapper calling the composite action; always overwritten; sync day is chosen interactively
5. **Pre-populates rules and skills** from upstream via GitHub API (so teammates get them immediately on next clone)
6. **Writes the guard hook** to `.claude/settings.json` — blocks accidental edits to sync-managed files
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

**Available categories**: `swift`, `ios`, `mac`, `visionos`, `xcode`, `android`, `web`

The `workflow` category is always synced — do not add it to `rules-sync.txt`.

---

## Rules

| File | Covers |
|------|--------|
| `rules/swift/analytics.md` | Firebase Analytics screen view tracking |
| `rules/swift/assets.md` | `ImageResource` in SwiftUI — type-safe, non-optional asset loading |
| `rules/swift/code-style.md` | Logger, file headers, import order, naming, SwiftLint |
| `rules/swift/concurrency.md` | `@MainActor`, `@Observable`, async patterns, Task discipline |
| `rules/swift/state-management.md` | `Loadable<T>` pattern, error surfacing, retry design |
| `rules/swift/swiftui.md` | View structure, adaptive layouts, state ownership, previews |
| `rules/swift/testing.md` | Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`) |
| `rules/ios/assets.md` | `UIImage(resource:)` — type-safe UIKit asset loading (iOS 17+) |
| `rules/mac/affordances.md` | Menus, keyboard shortcuts, windows, native chrome |
| `rules/visionos/realitykit.md` | RealityView lifecycle, entity rules, z-offset, attachments |
| `rules/android/code-style.md` | No force non-null, `Result<T>` at boundaries, companion constants |
| `rules/android/compose.md` | State management, lifecycle-aware collection, UI state coverage |
| `rules/android/room.md` | Flow from DAOs, KSP, explicit migrations, schema export |
| `rules/android/testing.md` | JUnit 4, Robolectric, MockK, Turbine for Flow assertions |
| `rules/web/playwright.md` | Playwright test execution vs visual verification |
| `rules/xcode/mcp-tools.md` | Xcode MCP tools for file ops, build, test, preview, code intelligence |
| `rules/xcode/packages.md` | SPM only — no CocoaPods or Carthage |
| `rules/xcode/warnings.md` | Zero-warning policy |
| `rules/workflow/contributing.md` | Cross-project rule contribution — invoke `lift-to-shared-rules` |
| `rules/workflow/synced-rules.md` | Synced-directory layout — where to put local rules, how to opt out |

---

## Skills

| Skill | What it does |
|-------|-------------|
| `lift-to-shared-rules` | Generalizes a pattern found in a project and proposes it upstream via commit (owner) or PR (contributor) |

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
