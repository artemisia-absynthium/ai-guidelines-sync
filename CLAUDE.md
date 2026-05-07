# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Central source of Claude Code rules for Swift, visionOS, and web projects, plus the `setup-project-ai` skill. Rules in `rules/` are synced into subscriber projects via GitHub Actions; the skill scaffolds subscriber projects with the sync workflow, directory structure, and category config.

## No build system

This repo has no package manager, build step, or test suite. There is nothing to install or run locally.

## Architecture

### Rules (`rules/`)

Domain-specific Claude Code rule files, split into category subdirectories: `swift/`, `visionos/`, `web/`. These are the **source of truth** — never edit them inside a subscriber repo's `.claude/rules/synced/`.

Changes here flow to subscriber projects on the next weekly sync (Mondays 9am UTC) or via manual `workflow_dispatch`. Each subscriber only receives the categories listed in its `.claude/rules-sync` file.

### Skill (`skills/setup-project-ai/SKILL.md`)

One-shot scaffolding skill: detects project type, creates `.claude/rules/synced/` and `.claude/skills/synced/` directories, writes `.claude/rules-sync` with the appropriate categories, and writes the sync workflow. It does **not** touch existing files in `.claude/rules/` or `.claude/skills/` outside of `synced/`, an existing `.claude/rules-sync`, other workflows, `CLAUDE.md`, or source files.

To bootstrap on a new machine: copy `skills/setup-project-ai/SKILL.md` to `~/.claude/skills/setup-project-ai/SKILL.md`. After the skill runs in a subscriber repo and the workflow is triggered once, skills are committed to `.claude/skills/synced/` and available team-wide — no per-machine setup needed after that.

### Design invariant

Any directory the sync workflow writes to must be `*/synced/`. Everything else in `.claude/rules/` and `.claude/skills/` is project-owned and never touched by sync. Never sync into a directory that teams might also write to directly.

### Sync model

Subscriber repos run a GitHub Actions workflow that checks out `artemisia-absynthium/claude-setup` and:
- Selectively rsyncs rule categories into `.claude/rules/synced/` (controlled by `.claude/rules-sync`)
- Rsyncs all skills into `.claude/skills/synced/` (no config needed — all skills are synced)

If `.claude/rules-sync` is absent, all rule categories are synced (backward-compatible default).

The workflow pushes via an SSH deploy key (`CLAUDE_RULES_DEPLOY_KEY` secret) to bypass branch protection on the subscriber's default branch.

### Category config (`.claude/rules-sync` in subscriber repos)

```
# Category names match directories under rules/ in artemisia-absynthium/claude-setup.
swift
visionos
```

Available categories: `swift`, `visionos`, `web`. Add a line to opt in to a new category; remove a line to stop receiving it. The sync workflow will delete previously-synced files for removed categories.

## Adding a deploy key to a subscriber repo

1. `ssh-keygen -t ed25519 -C "claude-rules-sync" -f /tmp/claude_rules_deploy_key -N ""`
2. `cat /tmp/claude_rules_deploy_key.pub | pbcopy` — copies public key to clipboard
   Subscriber repo → Settings → Deploy keys → add public key with **Allow write access**
3. Subscriber repo → Settings → Branches → edit branch protection → add deploy key to bypass list
4. `cat /tmp/claude_rules_deploy_key | pbcopy` — copies private key to clipboard
   Subscriber repo → Settings → Secrets → Actions → `CLAUDE_RULES_DEPLOY_KEY` → paste private key
5. Delete `/tmp/claude_rules_deploy_key*` when done
6. Trigger the sync workflow manually once via the Actions tab to populate `rules/synced/` and `skills/synced/`
