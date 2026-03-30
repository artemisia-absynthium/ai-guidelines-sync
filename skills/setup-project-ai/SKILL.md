# setup-project-ai

Scaffold an existing project for Claude Code rules infrastructure: creates the `shared/`/`local/`
directory structure, the sync workflow, and a project-specific architecture stub.

Run this once when enrolling an existing project that was not created from the template.
New projects created from `apple-project-template` already have all of this.

## Steps

1. **Detect project type** by reading the working directory:
   - `Package.swift` with `.visionOS` → visionOS (include visionos rules)
   - `Package.swift` with `.iOS` only → iOS
   - `build.gradle` / `build.gradle.kts` → Android/Kotlin
   - `package.json` → Node.js
   - `pyproject.toml` / `requirements.txt` → Python
   - Any `.swift` files → generic Swift fallback

2. **Create directory structure**:
   ```
   .claude/rules/shared/    ← managed by sync workflow, do not edit
   .claude/rules/local/     ← project-specific rules, owned by the team
   .github/workflows/       ← if not already present
   ```

3. **Write `.github/workflows/sync-claude-rules.yml`** using the template below.
   - Ask the user for their personal GitHub username to fill in the `repository:` field if it cannot be inferred.
   - Detect the default branch: run `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'` and use the result for `ref:` and `git push origin <branch>`. If the command returns nothing, ask the user.

   ```yaml
   name: Sync Claude Rules

   on:
     schedule:
       - cron: '0 9 * * 1'
     workflow_dispatch:

   jobs:
     sync:
       runs-on: ubuntu-latest
       permissions:
         contents: read  # push is via deploy key, not GITHUB_TOKEN
       steps:
         - name: Checkout project repo
           uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
           with:
             ssh-key: ${{ secrets.CLAUDE_RULES_DEPLOY_KEY }}
             ref: <DEFAULT_BRANCH>

         - name: Checkout claude-setup repo
           uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
           with:
             repository: artemisia-absynthium/claude-setup
             path: .tmp-claude-rules

         - name: Sync rules into shared/
           run: |
             mkdir -p .claude/rules/shared
             rsync -av --delete .tmp-claude-rules/rules/ .claude/rules/shared/
             rm -rf .tmp-claude-rules

         - name: Commit and push if changed
           run: |
             git config user.name "github-actions[bot]"
             git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
             git add .claude/rules/shared
             if git diff --cached --quiet; then
               echo "No rule changes — nothing to commit"
             else
               git commit -m "chore: sync Claude rules from upstream"
               git push origin <DEFAULT_BRANCH>
             fi
   ```

4. **Scaffold `.claude/rules/local/architecture.md`** only if it does not already exist:
   ```markdown
   ---
   description: <project name> architecture — key types, package structure, communication patterns
   alwaysApply: true
   ---

   # Architecture

   ## What this app is

   <!-- TODO: brief description -->

   ## Key types / ViewModels

   <!-- TODO: list the main state classes and their roles -->

   ## Package / module structure

   <!-- TODO: table of packages and their roles -->

   ## Communication patterns

   <!-- TODO: how layers communicate -->
   ```

5. **Report** to the user:
   - List what was created
   - List what was skipped (already existed)
   - Remind them to:
     1. Generate a deploy key and add it to the repo (see repo README for steps)
     2. Trigger the workflow manually once via the Actions tab to populate `shared/`
     3. Fill in `local/architecture.md` with project-specific details

## What this skill does NOT touch

- Any existing `.claude/rules/local/` files
- Any existing `.github/workflows/` files other than `sync-claude-rules.yml`
- `CLAUDE.md`, `README.md`, or any source files
