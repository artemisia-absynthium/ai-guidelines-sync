# Managed directory — do not edit manually

This directory is populated by `.github/workflows/sync-claude-rules.yml` from the
central `ai-guidelines-sync` repository. Any manual edits will be overwritten on the next
sync run (on the configured schedule, or on `workflow_dispatch`).

**To customize rules for this project**, add files to `.claude/rules/local/` instead.
That directory is never touched by the sync workflow.
