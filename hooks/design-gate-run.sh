#!/bin/bash
# Managed by ai-guidelines-sync — the design-gate runner.
# Launches a FRESH-CONTEXT reviewer (claude -p, read-only tools) with the fixed
# adversarial prompt in design-gate-prompt.md, parses its VERDICT line, and writes
# the stamp design-gate.sh checks. The authoring session never grades its own homework.
#
# Run manually before opening a PR (allow several minutes):
#   bash .claude/hooks/synced/design-gate-run.sh
# Model override: DESIGN_GATE_MODEL (default: opus).
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=design-gate-common.sh
. "${SCRIPT_DIR}/design-gate-common.sh"

PROMPT_FILE="${SCRIPT_DIR}/design-gate-prompt.md"
MODEL="${DESIGN_GATE_MODEL:-opus}"

fail() { echo "design-gate-run: $1" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || fail "claude CLI not found on PATH"
command -v jq >/dev/null 2>&1 || fail "jq not found on PATH"
[ -f "$PROMPT_FILE" ] || fail "reviewer prompt missing: $PROMPT_FILE"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository"

BRANCH=$(git rev-parse --abbrev-ref HEAD) || fail "cannot resolve current branch"
DEFAULT_BRANCH=$(gate_default_branch) || fail "cannot resolve the origin default branch"
BASE=$(git merge-base HEAD "origin/${DEFAULT_BRANCH}") || fail "cannot compute merge-base with origin/${DEFAULT_BRANCH}"
DIFF_HASH=$(gate_diff_hash) || fail "cannot hash the branch diff"

if git diff --quiet "${BASE}..HEAD"; then
    fail "no committed changes vs origin/${DEFAULT_BRANCH} — nothing to review"
fi

mkdir -p "$GATE_DIR"
# Self-gitignoring: the stamp and findings never enter version control.
[ -f "${GATE_DIR}/.gitignore" ] || printf '*\n' > "${GATE_DIR}/.gitignore"

PROMPT="$(cat "$PROMPT_FILE")

---
Repository: $(basename "$(git rev-parse --show-toplevel)")
Branch under review: ${BRANCH}
Review range: ${BASE}..HEAD (merge-base with origin/${DEFAULT_BRANCH})
Today: $(date -u +%Y-%m-%d)"

echo "design-gate-run: reviewing ${BRANCH} (${BASE}..HEAD) with model '${MODEL}' — this takes minutes..."

RESULT_JSON=$(claude -p "$PROMPT" \
    --model "$MODEL" \
    --output-format json \
    --allowedTools "Read Grep Glob Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git merge-base:*) Bash(git rev-parse:*)") || fail "claude -p failed"

REVIEW_TEXT=$(printf '%s' "$RESULT_JSON" | jq -r '.result // empty') || true
[ -n "${REVIEW_TEXT:-}" ] || fail "empty reviewer result — raw output kept in ${GATE_DIR}/last-raw.json"

printf '%s' "$RESULT_JSON" > "${GATE_DIR}/last-raw.json"
printf '%s\n' "$REVIEW_TEXT" > "$GATE_FINDINGS"

VERDICT=$(printf '%s\n' "$REVIEW_TEXT" | grep -E '^VERDICT: (PASS|FAIL)[[:space:]]*$' | tail -1 | awk '{print $2}') || true
[ -n "${VERDICT:-}" ] || fail "reviewer produced no VERDICT line — findings in ${GATE_FINDINGS}"

jq -n \
    --arg verdict "$VERDICT" \
    --arg diff_hash "$DIFF_HASH" \
    --arg branch "$BRANCH" \
    --arg model "$MODEL" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{verdict:$verdict, diff_hash:$diff_hash, branch:$branch, model:$model, timestamp:$timestamp}' \
    > "$GATE_STAMP"

echo ""
printf '%s\n' "$REVIEW_TEXT"
echo ""

if [ "$VERDICT" = "PASS" ]; then
    echo "design-gate-run: PASS — stamp written for diff ${DIFF_HASH}. The stamp invalidates on the next commit."
    exit 0
fi
echo "design-gate-run: FAIL — resolve the findings above (also in ${GATE_FINDINGS}) and re-run." >&2
exit 1
