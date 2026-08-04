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
5. **Pre-populates rules, skills, and hooks** from upstream via GitHub API (so teammates get them immediately on next clone)
6. **Writes the guard hook** to `.claude/settings.json` — blocks accidental edits to sync-managed files
7. **Wires the gate hooks** into `.claude/settings.json` — the design gate on PR creation, the hook-integrity guard, and the design-fit reminder (see [Hooks](#hooks--the-deterministic-layer))
8. **Migration** — renames `.claude/rules-sync` → `.claude/rules-sync.txt`, removes the retired `setup-project-ai` skill, cleans stale category directories

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
6. `rsync --delete` `hooks/` from upstream into `.claude/hooks/synced/` and restores the executable bits
7. Commits and pushes via the deploy key

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
| `rules/swift/coredata.md` | `NSManagedObjectContext` queue confinement — every access inside `perform` |
| `rules/swift/dates.md` | `FormatStyle` over `DateFormatter`, `en_US_POSIX` for machine formats |
| `rules/swift/security.md` | Archive extraction — containment-guarded APIs, zip-slip prevention |
| `rules/swift/state-management.md` | `Loadable<T>` pattern, error surfacing, retry design |
| `rules/swift/swiftui.md` | View structure, adaptive layouts, state ownership, previews, modal dismissal, in-app web |
| `rules/swift/testing.md` | Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`) |
| `rules/ios/assets.md` | `UIImage(resource:)` — type-safe UIKit asset loading (iOS 17+) |
| `rules/ios/liquid-glass.md` | Liquid Glass (iOS 26+) — system vs own glass, suppress-then-own, verification ladder |
| `rules/mac/affordances.md` | Menus, keyboard shortcuts, windows, native chrome |
| `rules/visionos/realitykit.md` | RealityView lifecycle, entity rules, z-offset, attachments |
| `rules/android/code-style.md` | No force non-null, `Result<T>` at boundaries, companion constants |
| `rules/android/compose.md` | State management, lifecycle-aware collection, UI state coverage |
| `rules/android/room.md` | Flow from DAOs, KSP, explicit migrations, schema export |
| `rules/android/testing.md` | JUnit 4, Robolectric, MockK, Turbine for Flow assertions |
| `rules/web/playwright.md` | Playwright test execution vs visual verification |
| `rules/xcode/mcp-tools.md` | Xcode MCP tools for file ops, build, test, preview, code intelligence |
| `rules/xcode/packages.md` | SPM only — no CocoaPods or Carthage |
| `rules/xcode/schemes.md` | GUI rewrites clobber hand-edited schemes; Run args leaking into the test host |
| `rules/xcode/test-destinations.md` | Run every supported platform; resolve destinations from the selected Xcode's SDK |
| `rules/xcode/warnings.md` | Zero-warning policy |
| `rules/workflow/build-discipline.md` | Build errors always in scope; human-intervention protocol |
| `rules/workflow/code-style.md` | Comment discipline (why, never what), TECH-DEBT annotations |
| `rules/workflow/contributing.md` | Cross-project rule contribution — invoke `lift-to-shared-rules` |
| `rules/workflow/design-gate.md` | The deterministic design gate — note, stamp, override protocol |
| `rules/workflow/design-principles.md` | SOLID from the start, SRP tripwire, full design-review lens |
| `rules/workflow/docs-sync.md` | Mandatory `Docs:` report line — README currency is part of done |
| `rules/workflow/expert-collaboration.md` | Design-fit checkpoint, "I don't know" protocol, discussion ≠ execution, mandatory dissent |
| `rules/workflow/planning-discipline.md` | Durable plan files, divergence as re-plan trigger, wire contracts |
| `rules/workflow/pr-review-gate.md` | Four review passes before any PR — design, code, security, concurrency |
| `rules/workflow/review-discipline.md` | Symmetric review protocol — invariants first, blast radius, mutation-checked tests |
| `rules/workflow/synced-rules.md` | Synced-directory layout — where to put local rules, how to opt out |
| `rules/xcode/schemes.md` | GUI edits clobber `.xcscheme`, test-action argument inheritance |

---

## Skills

| Skill | What it does |
|-------|-------------|
| `lift-to-shared-rules` | Generalizes a pattern found in a project and proposes it upstream via commit (owner) or PR (contributor) |
| `pr-review-gate` | The four mandatory review passes (design, standard, security, concurrency) before any PR opens — converted from an always-loaded rule to an on-demand skill |
| `design-review-lens` | Full design-review checklist (SOLID, Clean Architecture, GRASP, Clean Code, coupling laws) for the gate's design pass or standalone reviews |

After the first sync workflow run, skills are committed to `.claude/skills/<name>/` in each subscriber repo — available to all teammates automatically.

---

## Hooks — the deterministic layer

Rules steer Claude probabilistically; hooks are code and cannot be forgotten. `hooks/` syncs
into `.claude/hooks/synced/` in every subscriber, and `setup.sh` wires them into
`.claude/settings.json`:

| Hook | Event | What it does |
|------|-------|--------------|
| `design-gate.sh` | PreToolUse (Bash) | Blocks PR-opening commands (`gh pr create`/`ready`, `gh api`/REST/GraphQL equivalents) unless a valid gate stamp exists — PASS verdict, diff-hash matching the branch head, local HEAD pushed |
| `protect-gate-integrity.sh` | PreToolUse (Edit\|Write\|MultiEdit\|Bash) | Bash-command half of gate integrity (file-tool half is `permissions.deny` Edit rules written by setup.sh): denies touching synced hooks, settings wiring, the gate stamp, or their containers |
| `design-fit-reminder.sh` | UserPromptSubmit | Injects the design-fit scope check on every prompt |

### The design gate flow

1. Plan the feature; commit the design note (`Docs/design/<branch>.md` — see `rules/workflow/design-gate.md`)
2. Implement
3. `bash .claude/hooks/synced/design-gate-run.sh` — a **fresh-context** `claude -p` reviewer
   (read-only tools, fixed adversarial prompt: full design lens, blast-radius walk,
   test mutation-check, note conformance) prints findings and writes a stamp on PASS
4. Fix findings, re-run until PASS — the stamp invalidates on every new commit
5. Open the PR; the PR body carries the report lines the rule mandates

Model override: `DESIGN_GATE_MODEL=<model>` (default `opus`). Human-only escape hatch:
`DESIGN_GATE_OVERRIDE=1` — set it yourself, record it in the PR body; Claude is forbidden
from setting it.

### Hardening (optional)

Local hooks stop process failures; they cannot stop a deliberately misbehaving agent with
shell access. Two escalations, in order of strength:

- **Root-ownership**: `sudo chown root:wheel .claude .claude/hooks .claude/hooks/synced .claude/hooks/synced/* && sudo chmod go-w .claude .claude/hooks .claude/hooks/synced .claude/hooks/synced/*` —
  the parent directories must be root-owned too (renaming a directory needs write permission
  on its PARENT, so root-owning only the files still allows `mv .claude/hooks /tmp`).
  Honest limits: the stamp directory must stay user-writable (the runner runs as you), so
  root-ownership protects the hooks, never the stamp; and sync updates to hooks then require
  `sudo git checkout -- .claude/hooks/synced` locally.
- **Server-side enforcement** (the unconditional layer): run the same reviewer as a required
  GitHub status check with branch protection on the default branch. Not part of this repo yet.

### Existing subscribers

The sync action delivers hook *files*; it never edits `settings.json`. Repos enrolled
before hooks existed get the files on the next sync but stay inert until someone re-runs
`setup.sh` once (it wires the settings entries and the `permissions.deny` rules).
To decline hooks entirely, add a `# hooks` line to `.claude/rules-sync.txt` — both setup
and the action honor it.

### Mirror drift check

Rules mirrored into a private `~/.claude/rules/` (for repos not yet enrolled) carry a
`<!-- mirror-of: ai-guidelines-sync/rules/... -->` header. `scripts/check-rule-drift.sh`
diffs every mirror against its canonical here and reports drift.

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
