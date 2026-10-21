---
description: The sync's ownership and deletion contract — every managed path has an owner and a deletion story before it joins the sync — and what setup.sh and the composite action do
---

# Sync contract — ownership and deletion

The sync is a reconciliation loop, not a script: every run must converge any subscriber state
(including a half-failed previous run) to the table below. Each managed path has an explicit
owner, and the owner determines what an upstream deletion does to subscribers. **No path may be
added to the sync without adding its row here first** — a path without a deletion story is a
distribution mechanism without an ownership model, and the first revert is when you find out.

| Managed path (subscriber) | Owner | What a sync does | When upstream deletes it |
|---|---|---|---|
| `.claude/rules/synced/<cat>/` | Upstream | `rsync --delete` — the directory becomes exactly the upstream category | File (or whole category) disappears from every subscriber on its next sync |
| `.claude/skills/<name>/` | Mixed — upstream and local skills share the directory | rsync without `--delete`; the manifest `.claude/skills/.synced-manifest` records which names are upstream-owned | Deleted only if the manifest lists it; a local skill with the same name created *after* the manifest dropped it is invisible to the sync forever |
| `.claude/rules-sync.txt` | Subscriber (upstream appends detected categories) | Merge: auto-detected categories appended, commented lines respected as exclusions | n/a — never deleted by the sync |
| `.claude/settings.json` | Subscriber | `setup.sh` only: the script owns one `PreToolUse` entry whose command matches `rules/synced` (replaced on re-run) and one `permissions.deny` rule, `Agent(pr-review-toolkit:code-simplifier)` (appended when absent — the plugin subagent that rewrites code unasked is not a reviewer, `workflow/review.md`); everything else is merged around. An unusable file is primed — kept: every readable part; dropped with a warning: a non-object root or `hooks`, a non-array `PreToolUse`, `PreToolUse` entries that are not objects or whose `hooks`/`command` have the wrong type, a non-object `permissions`, a non-array `permissions.deny` and its non-string elements; the original is copied to `settings.json.before-priming` (never overwritten: an existing backup is a hard stop). A symlink at the file or at a sidecar name, a directory, or an unwritable file is a hard stop | n/a — never touched by the Action |
| Hook directories (Action) | — | No hook-directory step exists in the Action at present; if one returns, its contract is stated here first (previous incarnation: skip-when-source-absent, `rsync --delete` when present) | — |

Working *with* the grain of this contract: removing a skill upstream and re-creating it locally
in a subscriber (after one sync run) permanently hands that skill to the subscriber — the manifest
no longer tracks the name, so later syncs never touch it. This is the sanctioned way to fork a
skill for a local pilot; it reverses automatically when the skill is re-added upstream and a sync
re-adopts the name into the manifest.

## What `setup.sh` does

1. **Checks out the default branch and pulls** — re-reads the remote's default branch first (a
   clone's cached `origin/HEAD` goes stale when the default changes on GitHub). Skipped when the
   repo has no commits or no upstream. A dirty tree that is up to date proceeds; a clone behind its
   remote that cannot be fast-forwarded stops setup for that repo (listed under "Failed" in
   multi-repo mode, as is any repo where a later step could not write a file).
2. **Detects project type** from `.xcodeproj`, `Package.swift`, `build.gradle`, `package.json`,
   `playwright.config.*`, `pyproject.toml`.
3. **Writes `.claude/rules-sync.txt`** — skipped if it exists, preserving user edits.
4. **Writes `.github/workflows/sync-claude-rules.yml`** — always overwritten; sync day chosen
   interactively.
5. **Pre-populates rules and skills** from one tarball of this repo — outside the API rate
   limit, byte-identical to what the Action syncs.
6. **Writes the guard hook** to `.claude/settings.json`, per the table above.
7. **Migration** — renames `.claude/rules-sync` → `.claude/rules-sync.txt`, removes the retired
   `setup-project-ai` skill, cleans stale category directories.

Multi-repo mode collects per-repo failures and prints them at the end instead of aborting.

## What the composite action does

`.github/actions/sync/action.yml` holds all sync logic; subscriber workflows are thin wrappers
on `@main` and never change. Each run: checks out this repo alongside the subscriber; detects
project type and appends new categories to `rules-sync.txt` (commented lines are exclusions);
deletes `synced/<category>/` for removed categories; `rsync --delete` each active category into
`.claude/rules/synced/<category>/`; syncs skills through the manifest; commits and pushes via
the deploy key.
