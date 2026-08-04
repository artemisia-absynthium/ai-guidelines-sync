#!/bin/bash
# Managed by ai-guidelines-sync — PreToolUse guard (matcher: Bash).
# Blocks PR-opening commands unless a valid design-gate stamp exists: verdict PASS,
# stamp diff-hash matching the current branch diff, and local HEAD pushed.
# FAIL-CLOSED: once a command shows PR intent, any internal error denies (exit 2) —
# the hook API treats every other exit code as non-blocking.
# Protocol: rules/workflow/design-gate.md. Runner: design-gate-run.sh.
set -uo pipefail

INPUT=$(cat)

# Intent pre-check on the RAW payload, jq-free: if nothing PR-shaped appears anywhere,
# allow without further dependencies. Broad by design — false positives fall through to
# the precise (fail-closed) path below, never to a bypass.
if ! printf '%s' "$INPUT" | grep -qiE '(^|[^[:alpha:]])pr([^[:alpha:]]|$)|pull'; then
    exit 0
fi

deny() {
    echo "design-gate: $1" >&2
    echo "Run the gate first: bash .claude/hooks/synced/design-gate-run.sh (use a generous timeout — the review takes minutes), resolve its findings, then retry. Override is human-only: the user sets DESIGN_GATE_OVERRIDE=1 themselves." >&2
    exit 2
}

trap 'deny "internal error — failing closed"' ERR
command -v jq >/dev/null 2>&1 || deny "jq not found — the gate cannot inspect the command; install jq"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

# PR-opening intent, matched broadly (spelling variants, flags in any position, curl to
# the REST API, GraphQL mutations). Sub-resource reads/writes on an EXISTING PR
# (reviews, comments, single-PR reads) are carved out — reviewing is never gated.
GATED=false
STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's|pulls/[0-9]+[^[:space:]"'"'"']*||g')
if printf '%s' "$STRIPPED" | grep -qE 'gh[[:space:]].*\bpr[[:space:]]+(create|ready)\b'; then
    GATED=true
elif printf '%s' "$STRIPPED" | grep -qE '(gh[[:space:]]+api|curl[[:space:]]|api\.github\.com)' \
    && printf '%s' "$STRIPPED" | grep -qE '/?pulls([[:space:]"'"'"']|$)'; then
    GATED=true
elif printf '%s' "$STRIPPED" | grep -qE 'createPullRequest|markPullRequestReadyForReview'; then
    GATED=true
fi
[ "$GATED" = true ] || exit 0

# Human-only override — Claude never sets this (rules/workflow/design-gate.md).
if [ "${DESIGN_GATE_OVERRIDE:-0}" = "1" ]; then
    echo "design-gate: OVERRIDE active — PR allowed without a PASS stamp. Record the override and its reason in the PR body." >&2
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    # shellcheck source=design-gate-common.sh
    . "${SCRIPT_DIR}/design-gate-common.sh" 2>/dev/null \
        && [ -d "$GATE_DIR" ] \
        && printf 'OVERRIDE used at %s for: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMMAND" >> "$GATE_FINDINGS" 2>/dev/null
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=design-gate-common.sh
. "${SCRIPT_DIR}/design-gate-common.sh" || deny "cannot load design-gate-common.sh"

[ -f "$GATE_STAMP" ] || deny "no gate stamp found for this branch"

VERDICT=$(jq -r '.verdict // empty' "$GATE_STAMP" 2>/dev/null) || VERDICT=""
STAMP_HASH=$(jq -r '.diff_hash // empty' "$GATE_STAMP" 2>/dev/null) || STAMP_HASH=""

[ "${VERDICT:-}" = "PASS" ] || deny "last gate verdict was '${VERDICT:-invalid}' — findings in ${GATE_FINDINGS}"

CURRENT_HASH=$(gate_diff_hash) || deny "could not compute the branch diff hash"
[ "${STAMP_HASH:-}" = "$CURRENT_HASH" ] || deny "stamp is stale — the branch changed after the last gate run"

# The PR is built from the REMOTE branch; the stamp certifies LOCAL HEAD. Require them
# to be the same commit, or the gate would certify code the PR does not contain.
# Deliberately reads the local remote-tracking ref without fetching: a network call in a
# PreToolUse hook adds latency and failure modes to every gated command; the server-side
# required check is the layer that sees the true remote.
BRANCH=$(git rev-parse --abbrev-ref HEAD) || deny "cannot resolve the current branch"
REMOTE_SHA=$(git rev-parse "refs/remotes/origin/${BRANCH}" 2>/dev/null) || deny "branch '${BRANCH}' has no pushed counterpart — push first, then retry"
[ "$REMOTE_SHA" = "$(git rev-parse HEAD)" ] || deny "origin/${BRANCH} differs from local HEAD — push first, then retry"

exit 0
