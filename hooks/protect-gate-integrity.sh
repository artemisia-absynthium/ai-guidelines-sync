#!/bin/bash
# Managed by ai-guidelines-sync — PreToolUse integrity hook (matcher: Edit|Write|MultiEdit|Bash).
# Bash-command half of gate integrity: denies commands that touch the synced hooks, their
# settings wiring, or the design-gate stamp — including moving/removing their containers.
# The file-tool half is enforced by permissions.deny Edit() rules written by setup.sh
# (harness-normalized paths; Edit rules cover all file-editing tools); the file_path
# check here is belt-and-braces only.
# FAIL-CLOSED: this hook exits 2 on its own errors — the hook API treats any other
# non-zero exit as non-blocking.
set -uo pipefail

fail_closed() {
    echo "gate-integrity: internal error — failing closed. ${1:-}" >&2
    exit 2
}
trap 'fail_closed' ERR
command -v jq >/dev/null 2>&1 || fail_closed "jq not found; install jq"

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty') || FILE=""
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty') || CMD=""

deny() {
    echo "Blocked: synced hooks, their settings wiring, and the design-gate stamp are integrity-protected (.claude/hooks/synced/, .claude/settings*.json, .claude/design-gate/). Claude never modifies, disables, moves, or works around them — a hook that seems broken is diagnosed and reported to the user, who edits these files directly. The only permitted touch is 'bash .claude/hooks/synced/design-gate-run.sh' (single-line; it prints its findings, and only it writes the stamp)." >&2
    exit 2
}

if [ -n "$CMD" ]; then
    # The one legitimate touch of a protected path: executing the gate runner — as the
    # ONLY line of the command (a multi-line command could smuggle a second statement
    # past a per-line match), optionally quoted or absolute, with the model override
    # restricted to a plain model name (anything richer admits command substitution).
    if [ "$(printf '%s' "$CMD" | wc -l | tr -d ' ')" = "0" ] \
        && printf '%s' "$CMD" | grep -qE '^[[:space:]]*(DESIGN_GATE_MODEL=[A-Za-z0-9._-]+[[:space:]]+)?(bash|sh)[[:space:]]+["'"'"']?([^"'"'"';|&<>[:space:]]*/)?\.claude/hooks/synced/design-gate-run\.sh["'"'"']?[[:space:]]*$'; then
        exit 0
    fi

    # Protected content: any touch of the gate's paths, spelled directly or reached via
    # a split prefix (cd .claude && ... design-gate/...).
    if printf '%s' "$CMD" | grep -q '\.claude' \
        && printf '%s' "$CMD" | grep -qE 'hooks|design-gate|settings\.(local\.)?json|settings\.json'; then
        deny
    fi
    # Protected containers: relocating, deleting, de-executing, or link-aliasing any
    # .claude path disables the gate as surely as editing it.
    if printf '%s' "$CMD" | grep -q '\.claude' \
        && printf '%s' "$CMD" | grep -qE '(^|[[:space:];&|])(rm|mv|chmod|chown|ln|rmdir|truncate)[[:space:]]|git[[:space:]]+(checkout|clean|restore)[[:space:]]'; then
        deny
    fi
fi

if [ -n "$FILE" ]; then
    case "$FILE" in
        *".claude"*)
            printf '%s' "$FILE" | grep -qE 'hooks|design-gate|settings\.(local\.)?json|settings\.json' && deny
            ;;
    esac
fi

exit 0
