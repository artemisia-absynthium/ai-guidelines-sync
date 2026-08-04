#!/bin/bash
# check-rule-drift.sh — reports drift between private mirror rules and their upstream
# canonicals. A mirror is any file under ~/.claude/rules/ (or $1) whose first lines carry:
#   <!-- mirror-of: ai-guidelines-sync/rules/<category>/<file>.md ... -->
# Upstream is the local clone at $CLAUDE_SETUP_PATH (fallback: ~/Developer/ai-guidelines-sync).
# Comparison ignores the mirror header and the upstream YAML frontmatter.
set -uo pipefail

UPSTREAM="${CLAUDE_SETUP_PATH:-$HOME/Developer/ai-guidelines-sync}"
RULES_DIR="${1:-$HOME/.claude/rules}"

[ -d "$UPSTREAM" ] || { echo "upstream clone not found: $UPSTREAM (set CLAUDE_SETUP_PATH)" >&2; exit 1; }
[ -d "$RULES_DIR" ] || { echo "rules dir not found: $RULES_DIR" >&2; exit 1; }

# Strip mirror-header comment lines and a leading YAML frontmatter block, then
# collapse trailing blank lines, so only the rule body is compared.
normalized() {
    awk '
        NR <= 3 && /^<!--.*mirror-of:.*-->[[:space:]]*$/ { next }
        NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
        in_fm && /^---[[:space:]]*$/ { in_fm = 0; next }
        in_fm { next }
        { print }
    ' "$1" | awk 'NF { blanks = 0; print; next } { blanks++ } blanks == 1 { print "" }'
}

status=0
checked=0

for f in "$RULES_DIR"/*.md; do
    [ -f "$f" ] || continue
    ref=$(head -3 "$f" | grep -m1 -oE 'mirror-of:[[:space:]]*ai-guidelines-sync/[^[:space:]]+' \
        | sed 's|mirror-of:[[:space:]]*ai-guidelines-sync/||') || true
    [ -n "${ref:-}" ] || continue

    checked=$((checked + 1))
    up="${UPSTREAM}/${ref}"
    if [ ! -f "$up" ]; then
        echo "DRIFT  $f — upstream file missing: $ref (canonical pending, or moved)"
        status=1
        continue
    fi

    if diff -q <(normalized "$f") <(normalized "$up") >/dev/null 2>&1; then
        echo "OK     $f ↔ $ref"
    else
        echo "DRIFT  $f ↔ $ref — bodies differ (edit upstream, then re-mirror):"
        diff <(normalized "$f") <(normalized "$up") | head -20
        status=1
    fi
done

[ "$checked" -eq 0 ] && echo "No mirror-of headers found under $RULES_DIR — nothing to check."
exit "$status"
