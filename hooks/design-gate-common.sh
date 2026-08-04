#!/bin/bash
# Managed by ai-guidelines-sync — shared helpers sourced by the design-gate hooks.
# Synced into subscriber repos at .claude/hooks/synced/ — do not edit there.

gate_default_branch() {
    local b
    b=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|refs/remotes/origin/||') || true
    if [ -n "${b:-}" ]; then
        echo "$b"
        return 0
    fi
    for b in develop main master; do
        if git show-ref --verify --quiet "refs/remotes/origin/${b}"; then
            echo "$b"
            return 0
        fi
    done
    return 1
}

# Hash of the committed branch diff vs the merge-base with the default branch.
# The stamp is keyed to this: any commit after a gate run invalidates the stamp.
gate_diff_hash() {
    local branch base
    branch=$(gate_default_branch) || return 1
    base=$(git merge-base HEAD "origin/${branch}" 2>/dev/null) || return 1
    if command -v shasum >/dev/null 2>&1; then
        git diff "${base}..HEAD" | shasum -a 256 | awk '{print $1}'
    else
        git diff "${base}..HEAD" | sha256sum | awk '{print $1}'
    fi
}

GATE_DIR=".claude/design-gate"
GATE_STAMP="${GATE_DIR}/verdict.json"
GATE_FINDINGS="${GATE_DIR}/last-review.md"
