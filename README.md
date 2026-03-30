# claude-setup

Central source of Swift/visionOS Claude Code rules and project-setup skill.

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

Copy `skills/setup-project-ai/SKILL.md` to `~/.claude/skills/setup-project-ai/SKILL.md` to use it.

## Using rules in a project

Rules are synced as committed files so all teammates benefit regardless of their local setup.
Each project subscribes via a GitHub Actions workflow that pulls `rules/` into `.claude/rules/shared/` weekly.

Run `/setup-project-ai` in any existing project to install the workflow and directory structure.
New projects can be created from `apple-project-template` which includes all of this pre-wired.

## Adding a deploy key to a subscriber repo

The sync workflow pushes directly to `develop` bypassing branch protection via a deploy key:

1. Generate a key pair: `ssh-keygen -t ed25519 -C "claude-rules-sync" -f /tmp/claude_rules_deploy_key -N ""`
2. Subscriber repo → Settings → Deploy keys → Add deploy key → paste public key → enable **Allow write access**
3. Subscriber repo → Settings → Branches → edit `develop` rule → add the deploy key to the bypass list
4. Subscriber repo → Settings → Secrets → Actions → New secret → `CLAUDE_RULES_DEPLOY_KEY` → paste private key
5. Delete the key files from `/tmp/` when done
