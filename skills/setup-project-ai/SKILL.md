# setup-project-ai

Scaffold an existing project for Claude Code rules infrastructure: creates the `synced/`
directory structure and the sync workflow.

Run this once when enrolling an existing project that was not created from the template.
New projects created from `apple-project-template` already have all of this.

## Steps

1. **Detect project type** by reading the working directory:
   - `Package.swift` with `.visionOS` → visionOS (categories: `swift`, `visionos`)
   - `Package.swift` with `.iOS` only → iOS (categories: `swift`)
   - `build.gradle` / `build.gradle.kts` → Android/Kotlin (categories: `android`)
   - `package.json` + `playwright.config.*` present → web (categories: `web`)
   - `package.json` only → Node.js (categories: `node`)
   - `pyproject.toml` / `requirements.txt` → Python (categories: `python`)
   - Any `.swift` files → generic Swift fallback (categories: `swift`)

2. **Create directory structure**:
   ```
   .claude/rules/synced/    ← managed by sync workflow, do not edit
   .claude/skills/synced/   ← managed by sync workflow, do not edit
   .github/workflows/       ← if not already present
   ```

3. **Write `.claude/rules-sync`** only if it does not already exist. Use the categories detected in Step 1, one per line, with a comment header:
   ```
   # Sync config — managed by setup-project-ai skill
   # Edit this file to change which rule categories are synced into .claude/rules/synced/.
   # Category names match directories under rules/ in artemisia-absynthium/claude-setup.
   swift
   visionos
   ```

4. **Write `.github/workflows/sync-claude-rules.yml`** using the template below.
   - Ask the user for their personal GitHub username to fill in the `repository:` field if it cannot be inferred.

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
           run: |
             git config user.name "github-actions[bot]"
             git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
             git add .claude/rules/synced .claude/skills/synced
             if git diff --cached --quiet; then
               echo "No changes — nothing to commit"
             else
               git commit -m "chore: sync Claude rules and skills from upstream"
               git push origin "${{ github.event.repository.default_branch }}"
             fi
   ```

5. **Report** to the user:
   - List what was created
   - List what was skipped (already existed)
   - Remind them to:
     1. Generate a deploy key and add it to the repo (see repo README for steps)
     2. Trigger the workflow manually once via the Actions tab to populate `rules/synced/` and `skills/synced/`
     3. Run `/init` in the project root to generate CLAUDE.md with codebase context
     4. Edit `.claude/rules-sync` if the detected categories need adjusting

## What this skill does NOT touch

- Any existing files in `.claude/rules/` or `.claude/skills/` outside of `synced/`
- Any existing `.github/workflows/` files **other than** `sync-claude-rules.yml` (that file is always overwritten to pick up template updates)
- An existing `.claude/rules-sync` file (skip if present to preserve manual edits)
- `CLAUDE.md`, `README.md`, or any source files
