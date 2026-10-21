# ai-guidelines-sync

Shared Claude Code rules and skills for Swift, iOS, visionOS, macOS, Android and web projects.
One command enrols a repository; a scheduled GitHub Action keeps it current.

## Quick start

From the root of a repository, or from a directory that holds several:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artemisia-absynthium/ai-guidelines-sync/main/setup.sh)
```

The `<()` form matters: it keeps the terminal open for the interactive pickers. Run from inside
a repository to set up that one; run from a parent directory to pick several. Requires macOS
with Homebrew; `jq` is installed for the run if absent.

Re-running the script is the update command: your category choices are kept, everything else
is refreshed.

## What you get

- `.claude/rules/synced/<category>/` — the rule files for each category your project uses,
  owned by this repository: edit them here, never in the subscriber (a guard hook blocks it).
- `.claude/skills/<name>/` — the shared skills, next to your own.
- `.claude/rules-sync.txt` — your category choices.
- `.github/workflows/sync-claude-rules.yml` — a thin workflow that runs the sync on the day
  you pick; it never needs editing.

### Rule categories

| Category | Sync | Covers |
|----------|------|--------|
| `workflow` | always | How work is planned, written right the first time, built, tested, reviewed on request and contributed |
| `swift` | opt-in | The language and Apple frameworks on any Swift target — concurrency, SwiftUI, Swift Testing, Core Data, logging, SwiftLint, file layout, the Swift lines of the write-time checklist |
| `ios` | opt-in | iOS-only surfaces |
| `mac` | opt-in | macOS-only affordances — menus, shortcuts, windows |
| `visionos` | opt-in | RealityKit — RealityView lifecycle, entities, attachments |
| `xcode` | opt-in | Toolchain and project — the Xcode MCP, SPM, build configurations, schemes, test destinations, run verification |
| `android` | opt-in | Kotlin — code style, Compose, Room, testing |
| `web` | opt-in | Playwright |
| `database` | opt-in | Schema and transaction rules independent of the ORM |

Each file's title states its rule; browse `rules/<category>/` for the catalog.

### Skills

| Skill | What it does |
|-------|-------------|
| `create-pr` | Opens a pull request from the current branch, body from the repo's template, and reports what ran before it |
| `respond-to-pr-review` | Acts on a received review: reads every thread, decides approach versus patch per finding, shows you the replies, then replies and resolves in one pass |
| `design-review-lens` | The SOLID / Clean Architecture / GRASP checklist — on request, for a design review or a refactor |
| `swift-concurrency-review` | The Swift concurrency checklist — on request |
| `code-simplifier` | Simplifies the code a task just changed, on request, without changing what it does |
| `planning-discipline` | Four questions before any design, type-level design, invariant-first planning — for changes that do not fit in one sentence |
| `readme-drafting` | Writes a README as the maintainer addressing its reader — consumer of a library, contributor to an application — and nothing the reader does not act on |
| `lift-to-shared-rules` | Generalises a pattern from your project and proposes it here |

## Choosing categories — `.claude/rules-sync.txt`

One category per line. Comment a line out to exclude it; the sync will not add it back:

```
swift
ios
visionos
xcode
# mac   ← excluded on purpose
```

Available: `swift`, `ios`, `mac`, `visionos`, `xcode`, `android`, `web`, `database`.
`workflow` is always synced and is not listed. New categories the sync detects in your project
are appended unless you have commented them out.

## Letting the workflow push

The sync commits to your default branch through a deploy key:

1. `ssh-keygen -t ed25519 -C "claude-rules-sync" -f /tmp/claude_rules_deploy_key -N ""`
2. Public key → repository **Settings → Deploy keys → Add**, with **Allow write access**.
3. If the default branch is protected, add the key to the rule's bypass list.
4. Private key → **Settings → Secrets → Actions → `CLAUDE_RULES_DEPLOY_KEY`**.
5. `rm /tmp/claude_rules_deploy_key*`, then run the workflow once from the Actions tab.

## Contributing

Use the `lift-to-shared-rules` skill from any Claude Code session: it generalises the pattern,
anonymises it and opens the pull request. Rules here are generic engineering guidance,
publishable to strangers — no client, project or employer names.

Maintainers: `CLAUDE.md` and `.claude/rules/` in this repository hold the sync's ownership
contract and the shell constraints; `bats tests/` runs the `setup.sh` suite
(`brew install bats-core`).
