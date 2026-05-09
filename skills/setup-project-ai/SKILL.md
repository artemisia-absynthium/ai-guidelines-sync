# setup-project-ai

Scaffold an existing project for Claude Code rules infrastructure: creates the `synced/`
directory structure and the sync workflow.

Run this once when enrolling an existing project that was not created from the template.
New projects created from `apple-project-template` already have all of this.

## Steps

1. **Detect categories** by reading the working directory. Apple platform categories are
   **additive** — collect all that apply and union them. Non-Apple stacks are exclusive.

   **Swift / Apple baseline** — add when any Swift indicator is present:
   - Any `.swift` files, or `Package.swift` exists, or `.xcodeproj` is present → add `swift`, `xcode`

   **Apple platform additions** — check independently, on top of the baseline.
   App projects declare platforms in `project.pbxproj`; Swift packages declare them in
   `Package.swift`. Both are checked:
   - `project.pbxproj` contains `XROS_DEPLOYMENT_TARGET`, OR `Package.swift` contains `.visionOS` → add `visionos`
   - `project.pbxproj` contains `MACOSX_DEPLOYMENT_TARGET`, OR `Package.swift` contains `.macOS` → add `mac`

   **Non-Apple stacks** — exclusive, stop after first match:
   - `build.gradle` / `build.gradle.kts` → `android`
   - `package.json` + `playwright.config.*` present → `web`
   - `package.json` only → `node`
   - `pyproject.toml` / `requirements.txt` → `python`

   Examples: visionOS + iOS + Mac → `swift`, `xcode`, `visionos`, `mac`. iOS only →
   `swift`, `xcode`. Mac-only SwiftUI → `swift`, `xcode`, `mac`.

2. **Create directory structure**:
   ```
   .claude/rules/synced/    ← managed by sync workflow, do not edit
   .claude/skills/synced/   ← managed by sync workflow, do not edit
   .github/workflows/       ← if not already present
   ```

   Do not create `.gitkeep` or any other placeholder file inside these directories. They are populated in Step 5 below; an empty directory is acceptable until then.

3. **Write `.claude/rules-sync`** only if it does not already exist. Use the categories detected in Step 1, one per line, with a comment header:
   ```
   # Sync config — managed by setup-project-ai skill
   # Edit this file to change which rule categories are synced into .claude/rules/synced/.
   # Category names match directories under rules/ in artemisia-absynthium/claude-setup.
   swift
   visionos
   xcode
   ```

4. **Write `.github/workflows/sync-claude-rules.yml`** using the template below.
   - The `repository:` field is fixed as `artemisia-absynthium/claude-setup` — do not modify it.
   - Do **not** query the project's git remote (`git remote -v`, `git remote get-url`, etc.). The workflow does not need it.

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
         contents: write  # needed when CLAUDE_RULES_DEPLOY_KEY is absent; harmless when deploy key overrides auth
       steps:
         - name: Checkout project repo
           uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
           with:
             ssh-key: ${{ secrets.CLAUDE_RULES_DEPLOY_KEY }}
             ref: ${{ github.event.repository.default_branch }}

         - name: Checkout claude-setup repo
           uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
           with:
             repository: artemisia-absynthium/claude-setup
             path: .tmp-claude-rules

         - name: Migrate shared/ to synced/ (one-time)
           run: |
             for dir in ".claude/rules" ".claude/skills"; do
               if [[ -d "$dir/shared" && ! -d "$dir/synced" ]]; then
                 mv "$dir/shared" "$dir/synced"
                 echo "Migrated $dir/shared → $dir/synced"
               fi
             done

         - name: Sync rules into synced/
           run: |
             RULES_SRC=".tmp-claude-rules/rules"
             RULES_DST=".claude/rules/synced"
             CONFIG_FILE=".claude/rules-sync"

             mkdir -p "$RULES_DST"

             if [[ ! -f "$CONFIG_FILE" ]]; then
               echo "No $CONFIG_FILE found — syncing all categories (backward-compat mode)"
               rsync -av --delete "$RULES_SRC/" "$RULES_DST/"
             else
               echo "Reading categories from $CONFIG_FILE"
               RSYNC_ARGS=()
               while IFS= read -r line || [[ -n "$line" ]]; do
                 line="${line#"${line%%[![:space:]]*}"}"
                 line="${line%"${line##*[![:space:]]}"}"
                 [[ -z "$line" || "$line" == \#* ]] && continue
                 if [[ ! -d "$RULES_SRC/$line" ]]; then
                   echo "WARNING: category '$line' not found in upstream rules — skipping"
                   continue
                 fi
                 echo "  Syncing category: $line"
                 RSYNC_ARGS+=(--include="$line/***")
               done < "$CONFIG_FILE"

               if [[ ${#RSYNC_ARGS[@]} -eq 0 ]]; then
                 echo "ERROR: no valid categories found in $CONFIG_FILE — aborting to avoid wiping synced/"
                 exit 1
               fi

               rsync -av --delete \
                 --include="*/" \
                 "${RSYNC_ARGS[@]}" \
                 --exclude="*" \
                 "$RULES_SRC/" "$RULES_DST/"
             fi

         - name: Sync skills into .claude/skills/synced/
           run: |
             SKILLS_SRC=".tmp-claude-rules/skills"
             SKILLS_DST=".claude/skills/synced"
             mkdir -p "$SKILLS_DST"
             rsync -av --delete "$SKILLS_SRC/" "$SKILLS_DST/"
             rm -rf .tmp-claude-rules

         - name: Commit and push if changed
           env:
             DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}
           run: |
             git config user.name "github-actions[bot]"
             git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
             git add .claude/rules/synced .claude/skills/synced
             if git diff --cached --quiet; then
               echo "No changes — nothing to commit"
             else
               git commit -m "chore: sync Claude rules and skills from upstream"
               git push origin "$DEFAULT_BRANCH"
             fi
   ```

5. **Pre-populate `synced/` directories from upstream.** The project should be usable immediately — do not require a manual workflow trigger.

   Read `.claude/rules-sync` to get the list of selected categories (skip blank lines and lines starting with `#`). Then:

   ```bash
   TMP=$(mktemp -d -t claude-setup-bootstrap-XXXXXX)
   git clone --depth=1 https://github.com/artemisia-absynthium/claude-setup.git "$TMP"
   # For each category from .claude/rules-sync:
   rsync -a "$TMP/rules/<category>/" ".claude/rules/synced/<category>/"
   # All skills are synced (no per-skill config):
   rsync -a "$TMP/skills/" ".claude/skills/synced/"
   rm -rf "$TMP"
   ```

   Issue one `rsync` per category line. If a category directory does not exist in the upstream `rules/`, skip it with a warning and continue — do not abort.

   If the clone fails (offline / restricted network), report the failure explicitly and tell the user to trigger the workflow manually as a fallback. Do not leave half-populated state — if any rsync fails partway, remove what was copied so the next run is clean.

6. **Detect the project's default branch** before writing the report. Never assume `main`.

   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
   : "${DEFAULT_BRANCH:=<your default branch>}"
   ```

   Use `$DEFAULT_BRANCH` verbatim wherever the next-step text refers to the branch.

7. **Report** to the user. Stay strictly within the skill's scope:

   - **List what was created.** Only files this skill writes: the two `synced/` directories (now populated), `.claude/rules-sync` (if newly written), and `.github/workflows/sync-claude-rules.yml`.
   - **List what was skipped (already existed).** Only enumerate files this skill is responsible for — i.e. `.claude/rules-sync` if it pre-existed. Never report on `.claude/settings.json`, `.claude/settings.local.json`, `CLAUDE.md`, or anything else outside the skill's scope.
   - **Next steps**, in order:

     1. **Deploy key for branch-protected default branch (`$DEFAULT_BRANCH`).** If `$DEFAULT_BRANCH` has protection rules, the workflow's `GITHUB_TOKEN` cannot push and you must add a deploy key:
        1. Generate a key locally:
           ```bash
           ssh-keygen -t ed25519 -C "claude-rules-sync" -f /tmp/claude_rules_deploy_key -N ""
           ```
        2. GitHub → repo → **Settings → Deploy keys → Add deploy key**. Title: `claude-rules-sync`. Key: contents of `/tmp/claude_rules_deploy_key.pub`. **Check "Allow write access"**. Save.
        3. **Settings → Branches** → edit the protection rule for `$DEFAULT_BRANCH` → add the deploy key to the bypass list.
        4. **Settings → Secrets and variables → Actions → New repository secret**. Name: `CLAUDE_RULES_DEPLOY_KEY`. Value: contents of `/tmp/claude_rules_deploy_key` (the **private** key, no `.pub`).
        5. Clean up: `rm /tmp/claude_rules_deploy_key /tmp/claude_rules_deploy_key.pub`.

        If `$DEFAULT_BRANCH` has no branch protection, skip all of this — the workflow pushes via `GITHUB_TOKEN` (granted by `permissions: contents: write`).

     2. Run `/init` in the project root to generate or refresh `CLAUDE.md` with codebase context.
     3. Edit `.claude/rules-sync` if the detected categories need adjusting.

     The next scheduled run (Mondays 09:00 UTC) or any manual `workflow_dispatch` will keep `synced/` up to date from then on. **Do not** instruct the user to trigger the workflow manually for first-time population — Step 5 already populated it.

## What this skill does NOT touch

- Any existing files in `.claude/rules/` or `.claude/skills/` outside of `synced/`
- Any existing `.github/workflows/` files **other than** `sync-claude-rules.yml` (that file is always overwritten to pick up template updates)
- An existing `.claude/rules-sync` file (skip if present to preserve manual edits)
- `CLAUDE.md`, `README.md`, or any source files
- `.claude/settings.json`, `.claude/settings.local.json`, or any other settings file

The run report must not enumerate, comment on, or report the status of any file outside the skill's own scope (the `synced/` directories, `.claude/rules-sync`, and `sync-claude-rules.yml`). In particular, never mention `.claude/settings.json` or `.claude/settings.local.json` — they are not the skill's concern.
