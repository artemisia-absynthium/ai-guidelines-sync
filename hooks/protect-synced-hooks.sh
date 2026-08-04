#!/bin/bash
# Managed by ai-guidelines-sync — PreToolUse integrity hook (matcher: Edit|Write|MultiEdit|Bash).
# Denies modification of the synced hooks, their settings wiring, and the design-gate
# stamp. Covers the negligence/momentum failure class; for hard local immutability see
# the root-ownership step in the README. The unconditional layer is server-side CI.
set -uo pipefail

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

# The one legitimate touch of a protected path: executing the gate runner, bare.
# Anything else — including reads — is denied; the runner prints its findings to stdout.
if [ -n "${CMD:-}" ] && printf '%s' "$CMD" | grep -qE \
    '^[[:space:]]*(DESIGN_GATE_MODEL=[^[:space:]]+[[:space:]]+)?(bash|sh)[[:space:]]+(\./)?\.claude/hooks/synced/design-gate-run\.sh[[:space:]]*$'; then
    exit 0
fi

TARGET="${FILE:-} ${CMD:-}"

case "$TARGET" in
    *".claude/hooks/synced"*|*".claude/settings.json"*|*".claude/design-gate"*)
        echo "Blocked: synced hooks, their settings wiring, and the design-gate stamp are integrity-protected (.claude/hooks/synced/, .claude/settings.json, .claude/design-gate/). Claude never modifies, disables, or works around them — a hook that seems broken is diagnosed and reported to the user, who edits these files directly. The only permitted invocation is 'bash .claude/hooks/synced/design-gate-run.sh' (it prints its findings; the stamp is written only by it)." >&2
        exit 2
        ;;
esac

exit 0
