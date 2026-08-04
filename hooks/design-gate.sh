#!/bin/bash
# Managed by ai-guidelines-sync — PreToolUse guard (matcher: Bash).
# Blocks PR-opening commands unless a valid design-gate stamp exists:
# verdict PASS, and stamp diff-hash matching the current branch diff.
# Protocol: rules/workflow/design-gate.md. Runner: design-gate-run.sh.
set -uo pipefail

INPUT=$(cat)

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
[ -n "${CWD:-}" ] && cd "$CWD" 2>/dev/null

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
[ -n "${COMMAND:-}" ] || exit 0

# PR-opening commands only: gh pr create / gh pr ready / POST to .../pulls.
# ".../pulls/<n>/reviews" and other sub-resources must NOT match — reviews are not gated.
if ! printf '%s' "$COMMAND" | grep -qE \
    'gh[[:space:]]+pr[[:space:]]+(create|ready)|gh[[:space:]]+api[[:space:]]+[^[:space:]]*/pulls([[:space:]]|$)'; then
    exit 0
fi

# Human-only override — Claude never sets this (rules/workflow/design-gate.md).
if [ "${DESIGN_GATE_OVERRIDE:-0}" = "1" ]; then
    echo "design-gate: OVERRIDE active — PR allowed without a PASS stamp. Record the override and its reason in the PR body." >&2
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=design-gate-common.sh
. "${SCRIPT_DIR}/design-gate-common.sh"

deny() {
    echo "design-gate: $1" >&2
    echo "Run the gate first: bash .claude/hooks/synced/design-gate-run.sh (use a generous timeout — the review takes minutes), resolve its findings, then retry. Override is human-only: the user sets DESIGN_GATE_OVERRIDE=1 themselves." >&2
    exit 2
}

[ -f "$GATE_STAMP" ] || deny "no gate stamp found for this branch"

VERDICT=$(jq -r '.verdict // empty' "$GATE_STAMP" 2>/dev/null) || true
STAMP_HASH=$(jq -r '.diff_hash // empty' "$GATE_STAMP" 2>/dev/null) || true

[ "${VERDICT:-}" = "PASS" ] || deny "last gate verdict was '${VERDICT:-invalid}' — findings in ${GATE_FINDINGS}"

CURRENT_HASH=$(gate_diff_hash) || deny "could not compute the branch diff hash (no origin default branch?)"
[ "${STAMP_HASH:-}" = "$CURRENT_HASH" ] || deny "stamp is stale — the branch changed after the last gate run"

exit 0
