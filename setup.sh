#!/usr/bin/env bash
# AI Guidelines Sync — project setup script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/artemisia-absynthium/ai-guidelines-sync/main/setup.sh)
# See: https://github.com/artemisia-absynthium/ai-guidelines-sync
set -uo pipefail

UPSTREAM_REPO="artemisia-absynthium/ai-guidelines-sync"
UPSTREAM_API="https://api.github.com/repos/${UPSTREAM_REPO}"

# ── Output helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "  ${BLUE}${*}${NC}"; }
success() { echo -e "  ${GREEN}✓ ${*}${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ ${*}${NC}"; }
err()     { echo -e "${RED}Error: ${*}${NC}" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}${*}${NC}"; }

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

cleanup_deps() {
    if [ "$JQ_INSTALLED_BY_SCRIPT" = true ]; then
        warn "Removing jq (was installed temporarily)..."
        brew uninstall jq >/dev/null 2>&1 || true
    fi
}

trap cleanup_deps EXIT

# ── Git helpers ───────────────────────────────────────────────────────────────
checkout_default_and_pull() {
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|refs/remotes/origin/||') || true
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
        err "git pull --ff-only failed — resolve conflicts or divergence before running setup."
        return 1
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
        [[ -z "${line// }" ]] && continue
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
        mv ".claude/rules-sync" ".claude/rules-sync.txt"
        success "Renamed .claude/rules-sync → .claude/rules-sync.txt"
    fi

    local -a deprecated_skills=("setup-project-ai")
    local skill
    for skill in "${deprecated_skills[@]}"; do
        if [ -d ".claude/skills/$skill" ]; then
            rm -rf ".claude/skills/$skill"
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
    } > ".claude/rules-sync.txt"
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
            rm -rf "$cat_dir"
            success "Removed stale category directory: .claude/rules/synced/$cat_name/"
        fi
    done
}

write_workflow_file() {
    cat > ".github/workflows/sync-claude-rules.yml" <<WORKFLOW
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
    printf '%s\n' "$@" | sort -u > ".claude/skills/.synced-manifest"
    WRITTEN_FILES+=(".claude/skills/.synced-manifest")
}

# Fetch upstream rules and skills and write them into the project.
# Usage: sync_upstream <active_cat> [<active_cat> ...]
sync_upstream() {
    local -a active_cats=("$@")
    info "Fetching upstream file list..."
    local tree_json=""
    tree_json=$(curl -fsSL "${UPSTREAM_API}/git/trees/HEAD?recursive=1" 2>/dev/null) || true

    if ! ([ -n "$tree_json" ] && echo "$tree_json" | jq -e '.tree' >/dev/null 2>&1); then
        warn "Could not fetch upstream file list — skipping pre-population. Sync will run via GitHub Actions."
        return
    fi

    local -a upstream_paths=()
    local ac
    for ac in "${active_cats[@]}"; do
        while IFS= read -r p; do
            [ -n "$p" ] && upstream_paths+=("$p")
        done < <(echo "$tree_json" | jq -r --arg cat "$ac" \
            '.tree[] | select(.type=="blob") | .path | select(startswith("rules/"+$cat+"/"))' \
            2>/dev/null || true)
    done
    while IFS= read -r p; do
        [ -n "$p" ] && upstream_paths+=("$p")
    done < <(echo "$tree_json" | jq -r \
        '.tree[] | select(.type=="blob") | .path | select(startswith("skills/"))' \
        2>/dev/null || true)
    if ! hooks_opted_out; then
        while IFS= read -r p; do
            [ -n "$p" ] && upstream_paths+=("$p")
        done < <(echo "$tree_json" | jq -r \
            '.tree[] | select(.type=="blob") | .path | select(startswith("hooks/"))' \
            2>/dev/null || true)
    fi

    local upstream_path dest_path skill_name content
    local -a synced_skill_names=()
    for upstream_path in "${upstream_paths[@]}"; do
        if [[ "$upstream_path" == rules/* ]]; then
            dest_path=".claude/rules/synced/${upstream_path#rules/}"
        elif [[ "$upstream_path" == hooks/* ]]; then
            dest_path=".claude/hooks/synced/${upstream_path#hooks/}"
        else
            dest_path=".claude/${upstream_path}"
        fi
        mkdir -p "$(dirname "$dest_path")"
        content=$(curl -fsSL "${UPSTREAM_API}/contents/${upstream_path}" 2>/dev/null \
            | jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null) || {
            warn "Failed to fetch: $upstream_path"
            continue
        }
        printf '%s' "$content" > "$dest_path"
        if [[ "$dest_path" == .claude/hooks/synced/*.sh ]]; then
            # An empty or truncated hook would exit 0 forever — a gate that silently
            # stopped gating. Refuse to make anything without a shebang executable.
            if head -1 "$dest_path" | grep -q '^#!'; then
                chmod +x "$dest_path"
            else
                rm -f "$dest_path"
                warn "fetched hook is empty or malformed, discarded: $upstream_path"
                continue
            fi
        fi
        WRITTEN_FILES+=("$dest_path")
        if [[ "$upstream_path" == skills/* ]]; then
            skill_name=$(echo "$upstream_path" | cut -d/ -f2)
            synced_skill_names+=("$skill_name")
        fi
    done

    if [ "${#synced_skill_names[@]}" -gt 0 ]; then
        write_skills_manifest "${synced_skill_names[@]}"
    fi
}

merge_guard_hook() {
    local settings_file=".claude/settings.json"
    local guard_cmd
    # shellcheck disable=SC2016
    guard_cmd='file=$(jq -r '"'"'.file_path // empty'"'"'); case "$file" in *".claude/rules/synced"*) echo "ERROR: .claude/rules/synced/ is sync-managed — edits are overwritten on the next sync. Add rules to .claude/rules/ instead." >&2; exit 2;; esac'
    local guard_entry
    guard_entry=$(jq -n --arg cmd "$guard_cmd" \
        '{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":$cmd}]}')

    [ -f "$settings_file" ] || echo '{}' > "$settings_file"

    if grep -q "rules/synced" "$settings_file" 2>/dev/null; then
        SKIPPED_FILES+=(".claude/settings.json (guard hook already present)")
    else
        local tmp
        tmp=$(mktemp)
        jq --argjson entry "$guard_entry" \
            '.hooks = (.hooks // {}) | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$entry])' \
            "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
        WRITTEN_FILES+=(".claude/settings.json (guard hook added)")
    fi
}

# Wire the synced gate hooks into .claude/settings.json (idempotent per entry).
# Commands reference ${CLAUDE_PROJECT_DIR} literally — expanded by Claude Code at hook time.
# Each entry is wired only if its script actually landed (a failed upstream fetch must not
# leave settings pointing at nothing — a missing hook command is a NON-blocking error, so
# the gate would be silently inert). Opt-out: a "# hooks" line in rules-sync.txt.
GATE_HOOKS_WIRED=false

hooks_opted_out() {
    [ -f ".claude/rules-sync.txt" ] || return 1
    grep -qE '^[[:space:]]*#[[:space:]]*hooks[[:space:]]*$' ".claude/rules-sync.txt"
}

# merge_one_gate_entry <sentinel> <script-relpath> <jq-filter-with-$cmd>
merge_one_gate_entry() {
    local sentinel=$1 script=$2 filter=$3
    local settings_file=".claude/settings.json"
    # shellcheck disable=SC2016
    local base='${CLAUDE_PROJECT_DIR}/.claude/hooks/synced'
    local tmp

    if [ ! -f ".claude/hooks/synced/${script}" ]; then
        warn "hook not present, NOT wiring: ${script} (re-run setup after the first sync)"
        return 0
    fi
    if grep -q "$sentinel" "$settings_file" 2>/dev/null; then
        SKIPPED_FILES+=(".claude/settings.json (${sentinel} already present)")
        return 0
    fi
    tmp=$(mktemp)
    if jq --arg cmd "${base}/${script}" "$filter" "$settings_file" > "$tmp"; then
        mv "$tmp" "$settings_file"
        GATE_HOOKS_WIRED=true
    else
        rm -f "$tmp"
        warn ".claude/settings.json is not valid JSON — ${sentinel} NOT wired"
    fi
    return 0
}

merge_gate_hooks() {
    local settings_file=".claude/settings.json"
    if hooks_opted_out; then
        SKIPPED_FILES+=("gate hooks (opted out via '# hooks' in rules-sync.txt)")
        return 0
    fi
    [ -f "$settings_file" ] || echo '{}' > "$settings_file"

    merge_one_gate_entry "design-gate.sh" "design-gate.sh" \
        '.hooks = (.hooks // {}) | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":$cmd}]}])'
    merge_one_gate_entry "protect-gate-integrity.sh" "protect-gate-integrity.sh" \
        '.hooks = (.hooks // {}) | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{"matcher":"Edit|Write|MultiEdit|Bash","hooks":[{"type":"command","command":$cmd}]}])'
    merge_one_gate_entry "design-fit-reminder.sh" "design-fit-reminder.sh" \
        '.hooks = (.hooks // {}) | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":$cmd}]}])'

    # File-tool half of gate integrity: harness-normalized deny rules (Edit rules cover
    # ALL file-editing tools — a Write() rule would not match file permission checks).
    if ! grep -q 'design-gate/\*\*' "$settings_file" 2>/dev/null; then
        local tmp
        tmp=$(mktemp)
        if jq '.permissions = (.permissions // {}) | .permissions.deny = ((.permissions.deny // []) + ["Edit(.claude/hooks/synced/**)","Edit(.claude/design-gate/**)","Edit(.claude/settings.json)","Edit(.claude/settings.local.json)"] | unique)' \
            "$settings_file" > "$tmp"; then
            mv "$tmp" "$settings_file"
            GATE_HOOKS_WIRED=true
        else
            rm -f "$tmp"
            warn ".claude/settings.json is not valid JSON — integrity deny rules NOT added"
        fi
    fi

    if [ "$GATE_HOOKS_WIRED" = true ]; then
        WRITTEN_FILES+=(".claude/settings.json (gate hooks wired)")
        # The gate hooks make jq a permanent runtime dependency — never uninstall it.
        JQ_INSTALLED_BY_SCRIPT=false
    fi
    return 0
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
    echo "  4. Optional hardening — make the gate hooks locally immutable (root-owned):"
    echo "     sudo chown -R root:wheel .claude/hooks/synced && sudo chmod -R go-w .claude/hooks/synced"
    echo "     Trade-off: hook updates from sync then require 'sudo git checkout -- .claude/hooks/synced'"
}

setup_project() {
    header "Setting up: $(pwd)"
    WRITTEN_FILES=()
    SKIPPED_FILES=()

    checkout_default_and_pull || return 1

    migrate_legacy_files

    local cats_str
    cats_str=$(detect_categories ".")
    info "Detected categories: ${cats_str:-none}"

    setup_directories
    write_rules_sync_config "$cats_str"

    local -a active_cats=()
    while IFS= read -r _cat; do active_cats+=("$_cat"); done < <(read_active_categories)

    cleanup_stale_rules ${active_cats[@]+"${active_cats[@]}"}
    write_workflow_file
    sync_upstream ${active_cats[@]+"${active_cats[@]}"}
    merge_guard_hook
    merge_gate_hooks
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
            cd "$start_dir/$repo"
            setup_project
        ) || FAILED_REPOS+=("$repo")
    done

    if [ "${#FAILED_REPOS[@]}" -gt 0 ]; then
        echo -e "\n${YELLOW}Skipped (checkout/pull failed):${NC}"
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
