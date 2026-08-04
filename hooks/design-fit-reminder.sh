#!/bin/bash
# Managed by ai-guidelines-sync — UserPromptSubmit hook.
# stdout on exit 0 is injected as context: a deterministic reminder that fires on every
# prompt, so the design-fit checkpoint (rules/workflow/expert-collaboration.md) does not
# depend on recalling a rule buried under a long implementation context.
echo "Scope check: if this message adds or changes scope relative to a plan already in execution, STOP and evaluate design fit before any tool call — answer 'Design fit: unchanged because <reason>' or re-enter plan mode. Re-planning is expert practice, not failure."
exit 0
