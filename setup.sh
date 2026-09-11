#!/usr/bin/env bash
# AI Guidelines Sync — project setup script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/artemisia-absynthium/ai-guidelines-sync/main/setup.sh)
# See: https://github.com/artemisia-absynthium/ai-guidelines-sync
set -uo pipefail

UPSTREAM_REPO="artemisia-absynthium/ai-guidelines-sync"
# One archive download instead of one API call per file: codeload is not subject to the
# unauthenticated API quota (60/hour), which a single repo's ~40 files nearly exhausted.
UPSTREAM_ARCHIVE_URL="https://github.com/${UPSTREAM_REPO}/archive/HEAD.tar.gz"

# ── Output helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "  ${BLUE}${*}${NC}"; }
success() { echo -e "  ${GREEN}✓ ${*}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${*}${NC}"; }
err()     { echo -e "${RED}Error: ${*}${NC}" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}${*}${NC}"; }
# Every claim of a write sits in the success branch of that write; a failed write is
# reported here and the caller returns 1 — the run's output never names a write that
# did not happen, and the exit status says the run did not complete.
fail_write() { err "Could not write $1 — files written before this point are left in place; run: git status"; }

# ── Dependency management ─────────────────────────────────────────────────────
JQ_INSTALLED_BY_SCRIPT=false

ensure_jq() {
    command -v jq &>/dev/null && return 0

    if ! command -v brew &>/dev/null; then
        err "jq and Homebrew are both required."
        echo "Install Homebrew from https://brew.sh/, then install jq with: brew install jq"
        exit 1
    fi

    warn "jq not found — installing via Homebrew..."
    brew install jq >/dev/null
    JQ_INSTALLED_BY_SCRIPT=true
}

# State of an in-flight sync_upstream, so an interrupt at any point can be undone by the
# EXIT trap: the extraction dir, a partially written path, the previous copy of a category
# directory being swapped out (restored if the swap did not complete), and the local files
# a skill overlay has replaced (restored if the overlay did not complete).
UPSTREAM_TMP=""
UPSTREAM_STAGE=""
UPSTREAM_SWAP_OLD=""
UPSTREAM_SWAP_DEST=""
UPSTREAM_BACKUPS=()      # paths whose previous content sits at "<path>$UPSTREAM_BAK_SUFFIX"
UPSTREAM_SKILL_DEST=""   # skill directory being overlaid right now
UPSTREAM_SKILL_CREATED=false
UPSTREAM_SKILL_FILES=()  # files this run has written into it (or committed to writing)
UPSTREAM_SKILL_DIRS=()   # directories this run created inside it
# Sidecar names install_file writes next to a destination. Distinctive on purpose: the
# skills directory is shared with local files, and a plain ".tmp"/".bak" could collide.
UPSTREAM_TMP_SUFFIX=".ai-guidelines-sync.tmp"
UPSTREAM_BAK_SUFFIX=".ai-guidelines-sync.bak"

# Finish or undo a category swap left in flight. Safe to call when none is pending.
settle_swap() {
    if [ -n "$UPSTREAM_SWAP_OLD" ] && [ -e "$UPSTREAM_SWAP_OLD" ]; then
        if [ -e "$UPSTREAM_SWAP_DEST" ]; then
            rm -rf "$UPSTREAM_SWAP_OLD"          # swap completed; drop the previous copy
        elif ! mv "$UPSTREAM_SWAP_OLD" "$UPSTREAM_SWAP_DEST"; then
            warn "Could not restore $UPSTREAM_SWAP_DEST — its previous content is at $UPSTREAM_SWAP_OLD; move it back by hand."
        fi
    fi
    UPSTREAM_SWAP_OLD=""; UPSTREAM_SWAP_DEST=""
    return 0
}

# Put back the local files a skill overlay replaced (on rollback) — or, with drop=1,
# discard the backups (on success). Usage: settle_backups [drop]
settle_backups() {
    local drop="${1:-}" path
    for path in ${UPSTREAM_BACKUPS[@]+"${UPSTREAM_BACKUPS[@]}"}; do
        if [ -n "$drop" ]; then
            rm -f "$path$UPSTREAM_BAK_SUFFIX"
        elif [ -e "$path$UPSTREAM_BAK_SUFFIX" ] && ! mv -f "$path$UPSTREAM_BAK_SUFFIX" "$path"; then
            warn "Could not restore $path — its previous content is at $path$UPSTREAM_BAK_SUFFIX; move it back by hand."
        fi
    done
    UPSTREAM_BACKUPS=()
    return 0
}

# Undo a skill overlay that did not complete: a half-installed skill would be invisible
# to the manifest. Removes what this run wrote, restores what it replaced.
rollback_skill() {
    [ -n "$UPSTREAM_SKILL_DEST" ] || return 0
    if [ "$UPSTREAM_SKILL_CREATED" = true ]; then
        rm -rf "$UPSTREAM_SKILL_DEST"
        UPSTREAM_BACKUPS=()   # nothing pre-existed inside a dir this run created
    else
        local path
        for path in ${UPSTREAM_SKILL_FILES[@]+"${UPSTREAM_SKILL_FILES[@]}"}; do rm -f "$path"; done
        for path in ${UPSTREAM_SKILL_DIRS[@]+"${UPSTREAM_SKILL_DIRS[@]}"}; do rm -rf "$path"; done
        settle_backups        # put the replaced local files back
    fi
    UPSTREAM_SKILL_DEST=""; UPSTREAM_SKILL_CREATED=false; UPSTREAM_SKILL_FILES=(); UPSTREAM_SKILL_DIRS=()
    return 0
}

# Remove whatever an interrupted sync_upstream left in flight. Also trapped inside the
# per-repo subshell of multi-repo mode, which the parent's EXIT trap never reaches.
cleanup_upstream_tmp() {
    [ -n "$UPSTREAM_TMP" ] && rm -rf "$UPSTREAM_TMP"
    [ -n "$UPSTREAM_STAGE" ] && rm -rf "$UPSTREAM_STAGE"
    settle_swap
    rollback_skill
    settle_backups
    UPSTREAM_TMP=""; UPSTREAM_STAGE=""
    return 0
}

cleanup_deps() {
    cleanup_upstream_tmp
    if [ "$JQ_INSTALLED_BY_SCRIPT" = true ]; then
        warn "Removing jq (was installed temporarily)..."
        brew uninstall jq >/dev/null 2>&1 || true
    fi
}

trap cleanup_deps EXIT

# ── Git helpers ───────────────────────────────────────────────────────────────
checkout_default_and_pull() {
    local default_branch
    # Ask the remote for its current default branch: the clone-time origin/HEAD goes stale
    # when the default changes on the remote, and `git remote set-head --auto` refuses to
    # update it when the new default was never fetched. Offline, keep the cached value.
    default_branch=$(git ls-remote --symref origin HEAD 2>/dev/null \
        | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p') || true
    if [ -n "$default_branch" ]; then
        # Make the branch checkout-able even when it never existed at clone time, and
        # repair the cached origin/HEAD for tools that read it.
        git fetch --quiet origin >/dev/null 2>&1 || true
        git remote set-head origin "$default_branch" >/dev/null 2>&1 || true
    else
        default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's|refs/remotes/origin/||') || true
    fi
    : "${default_branch:=main}"

    # No commits yet — nothing to check out; proceed on current (empty) branch.
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        warn "Repository has no commits — skipping checkout and pull."
        return 0
    fi

    info "Checking out default branch: $default_branch"
    if ! git checkout "$default_branch"; then
        err "Failed to check out $default_branch."
        return 1
    fi

    # Skip pull when no upstream tracking branch is configured (e.g. no remote).
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
        warn "No upstream tracking branch — skipping pull."
        return 0
    fi

    info "Pulling latest changes..."
    if ! git pull --ff-only; then
        # A dirty tree alone is tolerated: the re-run-after-first-sync flow arrives with
        # the first run's own uncommitted writes, and setup is idempotent on the current
        # state. A clone that is *behind* its upstream is not: setup would write on a
        # stale base and the commit could not be pushed (or, rebased later, would
        # collide with the Action's own sync commits on the same files).
        local behind
        git fetch --quiet >/dev/null 2>&1 || true   # the current branch's upstream remote, i.e. what @{u} names
        behind=$(git rev-list --count HEAD..@{u} 2>/dev/null) || behind=0
        if [ "${behind:-0}" -gt 0 ]; then
            err "This clone is $behind commit(s) behind its upstream and could not be fast-forwarded (local changes, diverged history, or an unreachable remote). Commit or stash, rebase or merge onto the upstream, then re-run."
            return 1
        fi
        warn "git pull --ff-only failed — the clone is not behind its upstream, proceeding on the current state."
        return 0
    fi
}

# ── Interactive UI ────────────────────────────────────────────────────────────
SELECTED_DAY_NAME="Monday"
SELECTED_DAY_CRON=1
SELECTED_REPOS=()

# Show an arrow-key day picker. Sets SELECTED_DAY_NAME and SELECTED_DAY_CRON.
# In non-interactive mode, reads --day=<weekday> from args or defaults to Monday.
pick_day() {
    local -a days=("Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" "Sunday")
    local -a crons=(1 2 3 4 5 6 0)

    if [ ! -t 0 ]; then
        # Non-interactive: look for --day=<weekday> in args
        local day_arg=""
        for arg in "${@:-}"; do
            [[ "$arg" =~ ^--day=(.+)$ ]] && day_arg="${BASH_REMATCH[1]}" && break
        done
        local i
        for i in "${!days[@]}"; do
            if [ "$(echo "${days[$i]}" | tr '[:upper:]' '[:lower:]')" = "$(echo "$day_arg" | tr '[:upper:]' '[:lower:]')" ]; then
                SELECTED_DAY_NAME="${days[$i]}"
                SELECTED_DAY_CRON="${crons[$i]}"
                return
            fi
        done
        # Default: Monday
        SELECTED_DAY_NAME="Monday"; SELECTED_DAY_CRON=1
        return
    fi

    echo -e "${BOLD}Select sync day (↑↓ navigate, Enter/Space select, arrow to Confirm):${NC}"
    local cursor=0 selected=0 key key2  # pre-select Monday
    local i
    local total=$(( ${#days[@]} + 1 ))  # days + Confirm row

    tput civis 2>/dev/null || true
    for i in "${!days[@]}"; do
        printf "    [ ] %s\n" "${days[$i]}"
    done
    printf "    [ Confirm ]\n"

    while true; do
        tput cuu $total 2>/dev/null || true
        for i in "${!days[@]}"; do
            local mark=" "
            [ "$i" -eq "$selected" ] && mark="✓"
            if [ "$i" -eq "$cursor" ]; then
                printf "  \033[1;32m▶ [%s] %s\033[0m\n" "$mark" "${days[$i]}"
            else
                printf "    [%s] %s\n" "$mark" "${days[$i]}"
            fi
        done
        if [ "$cursor" -eq "${#days[@]}" ]; then
            printf "  \033[1;32m▶ [ Confirm ]\033[0m\n"
        else
            printf "    [ Confirm ]\n"
        fi

        IFS= read -r -s -n 1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n 2 key2 </dev/tty 2>/dev/null || key2=""
            case "$key2" in
                '[A') [ "$cursor" -gt 0 ] && ((cursor--)) || true ;;
                '[B') [ "$cursor" -lt $(( total - 1 )) ] && ((cursor++)) || true ;;
            esac
        elif [[ "$key" == "" || "$key" == " " ]]; then
            if [ "$cursor" -eq "${#days[@]}" ]; then
                break  # Confirm row — proceed
            else
                selected=$cursor  # Mark this day
            fi
        fi
    done

    tput cnorm 2>/dev/null || true
    SELECTED_DAY_NAME="${days[$selected]}"
    SELECTED_DAY_CRON="${crons[$selected]}"
    echo -e "\n${GREEN}✓ Sync day: ${SELECTED_DAY_NAME}${NC}"
}

# Show an arrow-key multi-select repo picker. Sets SELECTED_REPOS array.
pick_repos() {
    local -a repos=("$@")
    local -a sel=()
    local cursor=0 key key2
    local i

    for i in "${!repos[@]}"; do sel[$i]=0; done

    echo -e "${BOLD}Select repositories (↑↓ navigate, Enter/Space toggle, arrow to Confirm):${NC}"
    tput civis 2>/dev/null || true

    local total=$(( ${#repos[@]} + 1 ))  # repos + Confirm row

    for i in "${!repos[@]}"; do
        printf "    [ ] %s\n" "${repos[$i]}"
    done
    printf "    [ Confirm ]\n"

    while true; do
        tput cuu $total 2>/dev/null || true
        for i in "${!repos[@]}"; do
            local mark=" "
            [ "${sel[$i]}" -eq 1 ] && mark="✓"
            if [ "$i" -eq "$cursor" ]; then
                printf "  \033[1;32m▶ [%s] %s\033[0m\n" "$mark" "${repos[$i]}"
            else
                printf "    [%s] %s\n" "$mark" "${repos[$i]}"
            fi
        done
        if [ "$cursor" -eq "${#repos[@]}" ]; then
            printf "  \033[1;32m▶ [ Confirm ]\033[0m\n"
        else
            printf "    [ Confirm ]\n"
        fi

        IFS= read -r -s -n 1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n 2 key2 </dev/tty 2>/dev/null || key2=""
            case "$key2" in
                '[A') [ "$cursor" -gt 0 ] && ((cursor--)) || true ;;
                '[B') [ "$cursor" -lt $(( total - 1 )) ] && ((cursor++)) || true ;;
            esac
        elif [[ "$key" == "" || "$key" == " " ]]; then
            if [ "$cursor" -eq "${#repos[@]}" ]; then
                break  # Confirm row — proceed
            else
                sel[$cursor]=$(( 1 - sel[$cursor] ))  # Toggle
            fi
        fi
    done

    tput cnorm 2>/dev/null || true
    echo ""

    SELECTED_REPOS=()
    for i in "${!repos[@]}"; do
        [ "${sel[$i]}" -eq 1 ] && SELECTED_REPOS+=("${repos[$i]}")
    done
}

# ── Category detection ────────────────────────────────────────────────────────
# Echoes Apple-platform category names (one per line) for the given directory.
# Outputs nothing when no Swift project is detected.
_detect_apple_categories() {
    local dir="$1"
    local has_swift=false pbxproj=""

    if find "$dir" -maxdepth 3 -name "*.xcodeproj" -type d 2>/dev/null | head -1 | grep -q .; then
        has_swift=true
    elif [ -f "$dir/Package.swift" ]; then
        has_swift=true
    elif find "$dir" -maxdepth 3 -name "*.swift" \
            -not -path "*/.build/*" -not -path "*/DerivedData/*" 2>/dev/null | head -1 | grep -q .; then
        has_swift=true
    fi

    [ "$has_swift" = false ] && return

    echo "swift"
    echo "xcode"

    pbxproj=$(find "$dir" -name "*.pbxproj" \
        -not -path "*/.build/*" -not -path "*/DerivedData/*" 2>/dev/null | head -1 || true)

    if [ -n "$pbxproj" ]; then
        local platforms
        platforms=$(grep "SUPPORTED_PLATFORMS" "$pbxproj" 2>/dev/null | head -1 \
            | grep -oE '"[^"]*"' | tr -d '"' || true)

        if [ -z "$platforms" ]; then
            echo "ios"   # Absent → iOS only (Xcode default)
        else
            echo "$platforms" | grep -qE "xros|xrsimulator" && echo "visionos" || true
            echo "$platforms" | grep -q "macosx"            && echo "mac"      || true
            echo "$platforms" | grep -q "iphoneos"          && echo "ios"      || true
        fi
    elif [ -f "$dir/Package.swift" ]; then
        # Package.swift: check for 'platforms:' named argument (no leading dot — SPM syntax)
        if ! grep -qE '\bplatforms[[:space:]]*:' "$dir/Package.swift" 2>/dev/null; then
            echo "ios"; echo "visionos"; echo "mac"   # No platforms key → all platforms (SPM default)
        else
            grep -q '\.iOS'      "$dir/Package.swift" && echo "ios"      || true
            grep -q '\.visionOS' "$dir/Package.swift" && echo "visionos" || true
            grep -q '\.macOS'    "$dir/Package.swift" && echo "mac"      || true
        fi
    else
        echo "ios"   # Swift files, no project or package → assume iOS
    fi
}

# Outputs a space-separated list of detected category names to stdout.
detect_categories() {
    local dir="${1:-.}"
    local -a cats=()

    while IFS= read -r c; do cats+=("$c"); done < <(_detect_apple_categories "$dir")

    # ── Android ──
    if find "$dir" -maxdepth 3 \
            \( -name "build.gradle" -o -name "build.gradle.kts" \) 2>/dev/null | head -1 | grep -q .; then
        cats+=("android")
    fi

    # ── Web / Node ──
    if [ -f "$dir/package.json" ]; then
        if find "$dir" -maxdepth 2 -name "playwright.config.*" 2>/dev/null | head -1 | grep -q .; then
            cats+=("web")
        else
            cats+=("node")
        fi
    fi

    # ── Python ──
    if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ]; then
        cats+=("python")
    fi

    if [ "${#cats[@]}" -eq 0 ]; then
        echo ""
        return
    fi

    printf '%s\n' "${cats[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Print active (uncommented) categories from rules-sync.txt, one per line.
# 'workflow' is always included even if absent from the file.
# Usage: active_cats=( $(read_active_categories) )
read_active_categories() {
    echo "workflow"
    [ -f ".claude/rules-sync.txt" ] || return 0

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Trim surrounding whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        # A category is a bare directory name under rules/ — it becomes part of a path
        # that is deleted and rewritten, so anything else is refused, never interpreted.
        case "$line" in
            ''|*[!A-Za-z0-9_-]*)
                warn "Ignoring invalid category in .claude/rules-sync.txt: '$line'" >&2
                continue ;;
        esac
        # Don't duplicate workflow
        [ "$line" = "workflow" ] && continue
        echo "$line"
    done < ".claude/rules-sync.txt"
}

# ── Core setup functions ──────────────────────────────────────────────────────
WRITTEN_FILES=()
SKIPPED_FILES=()

migrate_legacy_files() {
    if [ -f ".claude/rules-sync" ] && [ ! -f ".claude/rules-sync.txt" ]; then
        mv ".claude/rules-sync" ".claude/rules-sync.txt" || { fail_write ".claude/rules-sync.txt"; return 1; }
        success "Renamed .claude/rules-sync → .claude/rules-sync.txt"
    fi

    local -a deprecated_skills=("setup-project-ai")
    local skill
    for skill in "${deprecated_skills[@]}"; do
        if [ -d ".claude/skills/$skill" ]; then
            rm -rf ".claude/skills/$skill" || { err "Could not remove .claude/skills/$skill"; return 1; }
            success "Removed deprecated synced skill: $skill"
        fi
    done
}

setup_directories() {
    mkdir -p ".claude/rules/synced" ".github/workflows" ".claude/skills"
}

# Write .claude/rules-sync.txt seeded with detected categories. Skips if already present.
# Usage: write_rules_sync_config "<space-separated category string>"
write_rules_sync_config() {
    local cats_str="$1"
    if [ -f ".claude/rules-sync.txt" ]; then
        SKIPPED_FILES+=(".claude/rules-sync.txt (already exists — preserving user edits)")
        return
    fi
    local -a detected_cats=()
    [ -n "$cats_str" ] && read -ra detected_cats <<< "$cats_str"
    {
        echo "# AI Guidelines Sync — category config"
        echo "# One category per line."
        echo "# Comment out a line (# category) to explicitly exclude it from auto-detection."
        echo "# Available: swift, ios, mac, visionos, xcode, android, web"
        echo "# The 'workflow' category is always synced regardless of this file."
        local cat
        if [ "${#detected_cats[@]}" -gt 0 ]; then
            for cat in "${detected_cats[@]}"; do echo "$cat"; done
        fi
    } > ".claude/rules-sync.txt" || { fail_write ".claude/rules-sync.txt"; return 1; }
    WRITTEN_FILES+=(".claude/rules-sync.txt")
}

# Remove .claude/rules/synced/* dirs whose category is no longer active.
# Usage: cleanup_stale_rules <active_cat> [<active_cat> ...]
cleanup_stale_rules() {
    # Temporary — handles repos set up before the action had category-level cleanup.
    # Can be removed after migration window (~2 weeks from initial rollout).
    [ -d ".claude/rules/synced" ] || return 0
    local -a active_cats=("$@")
    local cat_dir cat_name is_active ac
    for cat_dir in ".claude/rules/synced"/*/; do
        [ -d "$cat_dir" ] || continue
        cat_name=$(basename "$cat_dir")
        is_active=false
        for ac in ${active_cats[@]+"${active_cats[@]}"}; do
            [ "$ac" = "$cat_name" ] && is_active=true && break
        done
        if [ "$is_active" = false ]; then
            rm -rf "$cat_dir" || { err "Could not remove $cat_dir"; return 1; }
            success "Removed stale category directory: .claude/rules/synced/$cat_name/"
        fi
    done
}

write_workflow_file() {
    cat > ".github/workflows/sync-claude-rules.yml" <<WORKFLOW || { fail_write ".github/workflows/sync-claude-rules.yml"; return 1; }
# Managed by ai-guidelines-sync — do not edit this file directly.
# Sync logic lives in artemisia-absynthium/ai-guidelines-sync/.github/actions/sync@main.
# To change the sync day, re-run setup.sh and select a new day.
name: Sync Claude Rules and Skills

on:
  schedule:
    - cron: '0 9 * * ${SELECTED_DAY_CRON}'
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          ssh-key: \${{ secrets.CLAUDE_RULES_DEPLOY_KEY }}
      - uses: artemisia-absynthium/ai-guidelines-sync/.github/actions/sync@main
WORKFLOW
    WRITTEN_FILES+=(".github/workflows/sync-claude-rules.yml (${SELECTED_DAY_NAME})")
}

# Write .claude/skills/.synced-manifest. No-op when called with no arguments.
# Usage: write_skills_manifest <skill_name> [<skill_name> ...]
write_skills_manifest() {
    [ "$#" -eq 0 ] && return
    printf '%s\n' "$@" | sort -u > ".claude/skills/.synced-manifest" || { fail_write ".claude/skills/.synced-manifest"; return 1; }
    WRITTEN_FILES+=(".claude/skills/.synced-manifest")
}

# Copy one file into place through a temp name, so an interrupt never leaves a truncated
# file under a real name. An existing file is kept at "<dest>.bak" and recorded in
# UPSTREAM_BACKUPS so a later rollback can restore it. Usage: install_file <src> <dest>
install_file() {
    local src="$1" dest="$2"
    local tmp="$dest$UPSTREAM_TMP_SUFFIX" bak="$dest$UPSTREAM_BAK_SUFFIX"
    # mv onto an existing directory would move the temp file *inside* it and exit 0.
    [ -d "$dest" ] && return 1
    # The sidecar names are not ours to overwrite if something already sits there.
    if [ -e "$tmp" ] || [ -e "$bak" ]; then
        warn "Refusing to write $dest: $tmp or $bak already exists — remove it and re-run."
        return 1
    fi
    # Remember the topmost directory mkdir -p is about to create (if any), so a rollback
    # removes exactly what this run made and nothing that was already there.
    local parent top="" d
    parent=$(dirname "$dest"); d="$parent"
    while [ ! -e "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ] && [ "$d" != "$UPSTREAM_SKILL_DEST" ]; do
        top="$d"; d=$(dirname "$d")
    done
    [ -n "$top" ] && UPSTREAM_SKILL_DIRS+=("$top")   # recorded first: rm -rf tolerates absence
    mkdir -p "$parent" || return 1
    UPSTREAM_STAGE="$tmp"
    if ! cp "$src" "$UPSTREAM_STAGE"; then
        rm -f "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""
        return 1
    fi
    # If a file is there, move it to its backup — recorded *before* the move so an
    # interrupt in between still restores it (settle_backups skips backups that do not
    # exist).
    if [ -e "$dest" ]; then
        UPSTREAM_BACKUPS+=("$dest")
        if ! mv "$dest" "$bak"; then
            unset "UPSTREAM_BACKUPS[$(( ${#UPSTREAM_BACKUPS[@]} - 1 ))]"
            rm -f "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""
            return 1
        fi
    fi
    # Only now is $dest this run's to remove on rollback: the local content is safely at
    # $bak or was never there.
    UPSTREAM_SKILL_FILES+=("$dest")
    if ! mv "$UPSTREAM_STAGE" "$dest"; then
        rm -f "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""
        return 1
    fi
    UPSTREAM_STAGE=""
    return 0
}

# Replace a directory with a copy of another one. The new tree is assembled next to the
# destination, the old one is moved aside, the new one renamed in, and only then the old
# one deleted — every intermediate state is undone by cleanup_upstream_tmp.
# Usage: replace_dir <src_dir> <dest_dir>
replace_dir() {
    local src="$1" dest="$2"
    settle_swap   # never clobber a swap a previous call could not finish
    UPSTREAM_STAGE="$dest.new"
    rm -rf "$UPSTREAM_STAGE"
    if ! mkdir -p "$UPSTREAM_STAGE" || ! cp -R "$src/." "$UPSTREAM_STAGE/"; then
        rm -rf "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""
        return 1
    fi
    UPSTREAM_SWAP_DEST="$dest"
    UPSTREAM_SWAP_OLD="$dest.old"
    rm -rf "$UPSTREAM_SWAP_OLD"
    if [ -e "$dest" ] && ! mv "$dest" "$UPSTREAM_SWAP_OLD"; then
        rm -rf "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""; UPSTREAM_SWAP_OLD=""; UPSTREAM_SWAP_DEST=""
        return 1
    fi
    if ! mv "$UPSTREAM_STAGE" "$dest"; then
        rm -rf "$UPSTREAM_STAGE"; UPSTREAM_STAGE=""
        settle_swap   # restores .old, or warns and clears if even that fails
        return 1
    fi
    UPSTREAM_STAGE=""
    settle_swap       # dest exists now: drops .old
    return 0
}

# Fetch upstream rules and skills and write them into the project.
# Downloads one tarball of the upstream repo and copies from it, so the files are
# byte-identical to what the Action's rsync writes. Each active category directory is
# replaced wholesale (it is upstream-owned); skills are overlaid file by file without
# deleting, since the directory is shared with local skills — the manifest tracks the
# upstream names.
# Usage: sync_upstream <active_cat> [<active_cat> ...]
sync_upstream() {
    local -a active_cats=("$@")
    info "Fetching upstream rules and skills..."

    UPSTREAM_TMP=$(mktemp -d 2>/dev/null) || UPSTREAM_TMP=""
    if [ -z "$UPSTREAM_TMP" ] || ! curl -fsSL "$UPSTREAM_ARCHIVE_URL" 2>/dev/null \
        | tar -xzf - -C "$UPSTREAM_TMP" --strip-components=1 2>/dev/null \
        || [ ! -d "$UPSTREAM_TMP/rules" ]; then
        cleanup_upstream_tmp
        warn "Could not fetch upstream rules and skills — skipping pre-population. Sync will run via GitHub Actions."
        return
    fi

    local ac src dest f
    for ac in ${active_cats[@]+"${active_cats[@]}"}; do
        # read_active_categories already refuses these; re-checked here because the name
        # is about to be part of a path that is deleted and rewritten.
        case "$ac" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
        src="$UPSTREAM_TMP/rules/$ac"
        [ -d "$src" ] || continue
        dest=".claude/rules/synced/$ac"
        if ! replace_dir "$src" "$dest"; then
            warn "Failed to install category '$ac' — leaving the current one in place."
            continue
        fi
        while IFS= read -r f; do
            WRITTEN_FILES+=("$dest/${f#"$src/"}")
        done < <(find "$src" -type f | sort)
    done

    local -a synced_skill_names=()
    local skill_dir skill_name skill_ok
    for skill_dir in "$UPSTREAM_TMP"/skills/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        dest=".claude/skills/$skill_name"
        # Tracked in globals so an interrupt rolls the overlay back from the EXIT trap.
        UPSTREAM_SKILL_DEST="$dest"
        UPSTREAM_SKILL_CREATED=false; [ -e "$dest" ] || UPSTREAM_SKILL_CREATED=true
        UPSTREAM_SKILL_FILES=(); UPSTREAM_SKILL_DIRS=()
        skill_ok=true
        while IFS= read -r f; do
            if ! install_file "$f" "$dest/${f#"$skill_dir"}"; then
                skill_ok=false
                break
            fi
        done < <(find "$skill_dir" -type f | sort)
        if [ "$skill_ok" = true ]; then
            WRITTEN_FILES+=(${UPSTREAM_SKILL_FILES[@]+"${UPSTREAM_SKILL_FILES[@]}"})
            synced_skill_names+=("$skill_name")
            # Disarm the rollback before discarding the backups: an interrupt in between
            # then restores the local files instead of removing them with nothing to restore.
            UPSTREAM_SKILL_DEST=""; UPSTREAM_SKILL_CREATED=false; UPSTREAM_SKILL_FILES=(); UPSTREAM_SKILL_DIRS=()
            settle_backups drop
        else
            rollback_skill
            warn "Failed to install skill '$skill_name' — skipped, not recorded in the manifest."
        fi
    done

    cleanup_upstream_tmp

    if [ "${#synced_skill_names[@]}" -gt 0 ]; then
        write_skills_manifest "${synced_skill_names[@]}" || return 1
    fi
}

# ── settings.json shape ───────────────────────────────────────────────────────
# The rule at every level is "null or correctly typed": root object; hooks null/object;
# hooks.PreToolUse null/array; each entry an object whose hooks is null or an array of
# objects whose command is null or a string. One definition, shared by the predicate and
# the projection so they cannot drift (a $VAR inside a single-quoted jq program is a jq
# compile error, so sharing goes through a def prefix).
JQ_SETTINGS_DEFS='def entry_ok: (type == "object" and ((.hooks|type) == "null" or ((.hooks|type) == "array" and all(.hooks[]; type == "object" and ((.command|type) == "null" or (.command|type) == "string")))));'

# Usage: settings_json_usable <file>
# 0 when the file holds exactly one JSON document in the shape merge_guard_hook reads.
settings_json_usable() {
    jq -e -s "$JQ_SETTINGS_DEFS"'length == 1 and (.[0]
        | type == "object"
        and ((.hooks|type) == "null" or (.hooks|type) == "object")
        and ((.hooks.PreToolUse|type) == "null" or (.hooks.PreToolUse|type) == "array")
        and all(.hooks.PreToolUse // [] | .[]; entry_ok))' "$1" >/dev/null 2>&1 || return 1
}

# Usage: project_settings_document <file>
# Prints the document projected onto the shape: readable parts kept, unreadable parts
# dropped; absent keys stay absent, so the projection is the identity on a usable document.
# Anything but exactly one JSON document projects from {}.
project_settings_document() {
    local doc
    doc=$(jq -c -s 'if length == 1 then .[0] else {} end' "$1" 2>/dev/null) || doc='{}'
    printf '%s\n' "$doc" | jq "$JQ_SETTINGS_DEFS"'
        (if type == "object" then . else {} end)
        | (if (.hooks|type) == "null" or (.hooks|type) == "object" then . else del(.hooks) end)
        | (if (.hooks.PreToolUse|type) == "null" then .
           elif (.hooks.PreToolUse|type) == "array" then .hooks.PreToolUse |= map(select(entry_ok))
           else del(.hooks.PreToolUse) end)'
}

# Usage: back_up_settings_json <file>
# Copies the file beside itself before priming and prints the backup path. The backup is
# the recovery path for an uncommitted hand edit; git history is not.
back_up_settings_json() {
    local backup="$1.before-priming"
    [ -e "$backup" ] && backup="$backup.$(date +%s)"
    cp -p "$1" "$backup" || { fail_write "$backup"; return 1; }
    printf '%s\n' "$backup"
}

merge_guard_hook() {
    local settings_file=".claude/settings.json"
    local guard_cmd
    # shellcheck disable=SC2016
    guard_cmd='file=$(jq -r '"'"'.tool_input.file_path // empty'"'"'); case "$file" in *".claude/rules/synced"*) echo "ERROR: .claude/rules/synced/ is sync-managed — edits are overwritten on the next sync. Add rules to .claude/rules/ instead." >&2; exit 2;; esac'
    local guard_entry
    guard_entry=$(jq -n --arg cmd "$guard_cmd" \
        '{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":$cmd}]}')

    if [ -L "$settings_file" ] && [ ! -e "$settings_file" ]; then
        err "$settings_file is a dangling symlink — fix it and re-run."
        return 1
    fi
    [ -e "$settings_file" ] || echo '{}' > "$settings_file" || { fail_write "$settings_file"; return 1; }
    [ -f "$settings_file" ] || { err "$settings_file is not a regular file — fix it and re-run."; return 1; }

    local tmp="$settings_file.ai-guidelines-sync.tmp"
    if [ -e "$tmp" ]; then
        err "$tmp exists — a previous run was interrupted; inspect and remove it, then re-run."
        return 1
    fi

    # An unusable file (the script's own earlier output, a hand edit with a stray comma, a
    # bare hook entry at the root) is primed rather than refused: the update command must
    # not fail where the user did nothing. Readable parts are kept, the original is backed
    # up, and the warning says so — including that keys from the old shape may remain.
    local doc primed=false backup
    if settings_json_usable "$settings_file"; then
        doc=$(cat "$settings_file")
    else
        backup=$(back_up_settings_json "$settings_file") || return 1
        doc=$(project_settings_document "$settings_file")
        primed=true
        warn "$settings_file was not in the shape Claude Code reads and was primed: readable parts kept, the rest dropped (original at $backup). Review with git diff — keys from the old shape may remain."
    fi

    # "Already present" means the exact current command. A guard that merely mentions
    # rules/synced is an outdated variant and is replaced: guards written before the
    # tool_input fix read .file_path, which the PreToolUse payload never carries, so they
    # never fired — a re-run of this script must repair them, not skip them. A primed
    # document is never skipped: it was rewritten, so it is written and reported as such.
    if [ "$primed" = false ] && printf '%s\n' "$doc" | jq -e --arg cmd "$guard_cmd" \
        '[.hooks.PreToolUse // [] | .[] | (.hooks // [])[] | (.command // "")] | any(. == $cmd)' \
        >/dev/null 2>&1; then
        SKIPPED_FILES+=(".claude/settings.json (guard hook already present)")
        return 0
    fi

    local outdated
    outdated=$(printf '%s\n' "$doc" | jq '[.hooks.PreToolUse // [] | .[]
        | select((.hooks // []) | map((.command // "") | test("rules/synced")) | any)] | length')

    # jq must never read the file it writes: the sidecar is renamed over the file only once
    # the whole document is on disk.
    if printf '%s\n' "$doc" | jq --argjson entry "$guard_entry" '
        .hooks = (.hooks // {})
        | .hooks.PreToolUse = ([.hooks.PreToolUse // [] | .[]
            | select(((.hooks // []) | map((.command // "") | test("rules/synced")) | any) | not)]
            + [$entry])' > "$tmp" && mv "$tmp" "$settings_file"; then
        local what="guard hook added"
        if [ "$outdated" -gt 0 ]; then what="guard hook updated"; fi
        if [ "$primed" = true ]; then what="settings primed, $what"; fi
        WRITTEN_FILES+=(".claude/settings.json ($what)")
    else
        rm -f "$tmp"
        fail_write "$settings_file"
        return 1
    fi
}

report_results() {
    echo ""
    echo -e "${BOLD}${GREEN}Done — $(pwd)${NC}"
    if [ "${#WRITTEN_FILES[@]}" -gt 0 ]; then
        echo -e "${GREEN}Written:${NC}"
        local f
        for f in "${WRITTEN_FILES[@]}"; do echo "  • $f"; done
    fi
    if [ "${#SKIPPED_FILES[@]}" -gt 0 ]; then
        echo -e "${YELLOW}Skipped:${NC}"
        for f in "${SKIPPED_FILES[@]}"; do echo "  • $f"; done
    fi
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. If this repo has branch protection, add a deploy key:"
    echo "     See: https://github.com/artemisia-absynthium/ai-guidelines-sync#adding-a-deploy-key"
    echo "  2. Commit and push all new/modified files"
    echo "  3. Actions → Sync Claude Rules and Skills → Run workflow (to verify the action runs)"
}

setup_project() {
    header "Setting up: $(pwd)"
    WRITTEN_FILES=()
    SKIPPED_FILES=()

    checkout_default_and_pull || return 1

    migrate_legacy_files || return 1

    local cats_str
    cats_str=$(detect_categories ".")
    info "Detected categories: ${cats_str:-none}"

    setup_directories
    write_rules_sync_config "$cats_str" || return 1

    local -a active_cats=()
    while IFS= read -r _cat; do active_cats+=("$_cat"); done < <(read_active_categories)

    cleanup_stale_rules ${active_cats[@]+"${active_cats[@]}"} || return 1
    write_workflow_file || return 1
    sync_upstream ${active_cats[@]+"${active_cats[@]}"} || return 1
    merge_guard_hook || return 1
    report_results
}

# ── Multi-repo mode ───────────────────────────────────────────────────────────
multi_repo_mode() {
    header "Multi-repo mode — scanning for git repositories..."
    echo ""

    local -a repos=()
    while IFS= read -r repo; do
        repo="${repo#./}"
        [ -n "$repo" ] && [ "$repo" != "." ] && repos+=("$repo")
    done < <(find . \
        \( -name "node_modules" -o -name "Pods" -o -name ".build" \
           -o -name "DerivedData" -o -name "vendor" -o -name "dist" \) -prune \
        -o -name ".git" -type d -print 2>/dev/null \
        | sed 's|/.git$||' | sort)

    if [ "${#repos[@]}" -eq 0 ]; then
        err "No git repositories found in $(pwd)"
        exit 1
    fi

    pick_repos "${repos[@]}"

    if [ "${#SELECTED_REPOS[@]}" -eq 0 ]; then
        warn "No repositories selected."
        exit 0
    fi

    pick_day "${@:-}"

    echo ""
    header "Running setup on ${#SELECTED_REPOS[@]} repo(s)..."

    local start_dir
    start_dir="$(pwd)"
    local repo
    local -a FAILED_REPOS=()

    for repo in "${SELECTED_REPOS[@]}"; do
        (
            trap cleanup_upstream_tmp EXIT
            cd "$start_dir/$repo" || exit 1
            setup_project
        ) || FAILED_REPOS+=("$repo")
    done

    if [ "${#FAILED_REPOS[@]}" -gt 0 ]; then
        echo -e "\n${YELLOW}Failed (see errors above):${NC}"
        local r
        for r in "${FAILED_REPOS[@]}"; do echo "  • $r"; done
    fi
    echo -e "\n${BOLD}${GREEN}All done!${NC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    ensure_jq

    if git rev-parse --git-dir >/dev/null 2>&1; then
        pick_day "${@:-}"
        setup_project || exit 1
    else
        multi_repo_mode "${@:-}"
    fi
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
