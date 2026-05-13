# lift-to-shared-rules

Persist a generalizable coding pattern into the shared rules repo at `~/Developer/claude-setup`, verify coherence across all existing rules, show the diff, and propose a commit+push.

Invoke this skill whenever a pattern, constraint, or convention emerges that should apply across all projects, not just the current one.

## Steps

1. **Identify target**

   Determine the category and file:
   - Categories: `swift`, `visionos`, `xcode`, `mac`, `android`, `web`
   - Map the rule to the most specific applicable category
   - Target file: `~/Developer/claude-setup/rules/<category>/<topic>.md`
   - If no existing file fits, create a new one with a descriptive name

2. **Write the change**

   Edit or create the target file. Rule files use this frontmatter format:

   ```markdown
   ---
   description: <one-line summary — shown in skill/rule pickers>
   globs:
     - "**/*.swift"   # adjust to the file types this rule applies to
   ---

   # Rule Title

   <content>
   ```

   Write the rule in the same style as existing files in the repo: direct, imperative, code examples where they clarify rather than pad.

3. **Check coherence**

   Read every file under `~/Developer/claude-setup/rules/` (all categories). For each, check:
   - **Duplication**: does the new content repeat something already stated elsewhere?
   - **Contradiction**: does the new content conflict with an existing rule?
   - **Merge opportunity**: should the new content extend an existing file rather than live in a new one?

   If issues are found and the resolution is clear, apply it before proceeding — either by adjusting the new content or updating the conflicting existing file. If the resolution is ambiguous, stop and ask the user how to proceed before making any further changes.

4. **Show the diff**

   ```bash
   git -C ~/Developer/claude-setup diff
   git -C ~/Developer/claude-setup status
   ```

   Present the full diff to the user. List any coherence issues found in Step 3 and how they were resolved.

5. **Propose commit and ask for confirmation**

   Draft a commit message following the repo's style (`chore:` or descriptive imperative). Present it and wait for the user to confirm before committing.

6. **Commit and push**

   On confirmation:

   ```bash
   git -C ~/Developer/claude-setup add -A
   git -C ~/Developer/claude-setup commit -m "<message>"
   git -C ~/Developer/claude-setup push
   ```

   Report success or any errors.

## What this skill does NOT touch

- Files outside `~/Developer/claude-setup/rules/` and `~/Developer/claude-setup/skills/`
- Project-level CLAUDE.md files or `.claude/rules/` directories in any project repo
- The sync workflow (`.github/workflows/sync-claude-rules.yml`)
