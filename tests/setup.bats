#!/usr/bin/env bats
# Tests for setup.sh — run with: bats tests/
# Requires: BATS (brew install bats-core), jq

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  # Source setup.sh to load functions without running main().
  # The BASH_SOURCE guard in setup.sh prevents main() from executing.
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/setup.sh"
  WRITTEN_FILES=()
  SKIPPED_FILES=()
  SELECTED_DAY_CRON=1
  SELECTED_DAY_NAME="Monday"
  JQ_INSTALLED_BY_SCRIPT=false
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── detect_categories ─────────────────────────────────────────────────────────

@test "detect_categories: empty directory outputs nothing" {
  result=$(detect_categories "$TEST_DIR")
  [ -z "$result" ]
}

@test "detect_categories: xcodeproj detects swift and xcode" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"swift"* ]]
  [[ "$result" == *"xcode"* ]]
}

@test "detect_categories: pbxproj without SUPPORTED_PLATFORMS means ios" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  echo '// no SUPPORTED_PLATFORMS' > "$TEST_DIR/MyApp.xcodeproj/project.pbxproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"ios"* ]]
  [[ "$result" != *"visionos"* ]]
  [[ "$result" != *"mac"* ]]
}

@test "detect_categories: pbxproj with iphoneos means ios only" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  echo 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";' \
    > "$TEST_DIR/MyApp.xcodeproj/project.pbxproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"ios"* ]]
  [[ "$result" != *"visionos"* ]]
  [[ "$result" != *"mac"* ]]
}

@test "detect_categories: pbxproj with xros means visionos only" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  echo 'SUPPORTED_PLATFORMS = "xros xrsimulator";' \
    > "$TEST_DIR/MyApp.xcodeproj/project.pbxproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"visionos"* ]]
  [[ "$result" != *"ios"* ]]
  [[ "$result" != *"mac"* ]]
}

@test "detect_categories: pbxproj with macosx means mac only" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  echo 'SUPPORTED_PLATFORMS = "macosx";' \
    > "$TEST_DIR/MyApp.xcodeproj/project.pbxproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"mac"* ]]
  [[ "$result" != *"ios"* ]]
  [[ "$result" != *"visionos"* ]]
}

@test "detect_categories: pbxproj with all platforms detects all three" {
  mkdir -p "$TEST_DIR/MyApp.xcodeproj"
  echo 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator";' \
    > "$TEST_DIR/MyApp.xcodeproj/project.pbxproj"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"ios"* ]]
  [[ "$result" == *"mac"* ]]
  [[ "$result" == *"visionos"* ]]
}

@test "detect_categories: Package.swift without platforms key means all platforms" {
  echo 'let package = Package(name: "Foo")' > "$TEST_DIR/Package.swift"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"ios"* ]]
  [[ "$result" == *"visionos"* ]]
  [[ "$result" == *"mac"* ]]
}

@test "detect_categories: Package.swift with iOS platform means ios only" {
  # Uses 'platforms:' named arg (no leading dot) — the real SPM format
  echo 'let package = Package(name: "Foo", platforms: [.iOS(.v17)])' \
    > "$TEST_DIR/Package.swift"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"ios"* ]]
  [[ "$result" != *"visionos"* ]]
  [[ "$result" != *"mac"* ]]
}

@test "detect_categories: Package.swift with visionOS platform means visionos only" {
  echo 'let package = Package(name: "Foo", platforms: [.visionOS(.v1)])' \
    > "$TEST_DIR/Package.swift"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"visionos"* ]]
  [[ "$result" != *"ios"* ]]
}

@test "detect_categories: build.gradle detects android" {
  echo "apply plugin: 'com.android.application'" > "$TEST_DIR/build.gradle"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"android"* ]]
}

@test "detect_categories: build.gradle.kts detects android" {
  echo 'plugins { id("com.android.application") }' > "$TEST_DIR/build.gradle.kts"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"android"* ]]
}

@test "detect_categories: package.json alone detects node" {
  echo '{"name": "my-app", "version": "1.0.0"}' > "$TEST_DIR/package.json"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"node"* ]]
  [[ "$result" != *"web"* ]]
}

@test "detect_categories: package.json plus playwright config detects web not node" {
  echo '{"name": "my-app"}' > "$TEST_DIR/package.json"
  touch "$TEST_DIR/playwright.config.ts"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"web"* ]]
  [[ "$result" != *"node"* ]]
}

@test "detect_categories: pyproject.toml detects python" {
  echo '[tool.poetry]' > "$TEST_DIR/pyproject.toml"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"python"* ]]
}

@test "detect_categories: requirements.txt detects python" {
  echo 'requests==2.31.0' > "$TEST_DIR/requirements.txt"
  result=$(detect_categories "$TEST_DIR")
  [[ "$result" == *"python"* ]]
}

# ── merge_guard_hook ──────────────────────────────────────────────────────────

@test "merge_guard_hook: added to empty settings.json" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  count=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  [ "$count" = "1" ]
}

@test "merge_guard_hook: existing PostToolUse entry is preserved" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{"hooks":{"PostToolUse":[]}}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  result=$(jq '.hooks | has("PostToolUse")' "$TEST_DIR/.claude/settings.json")
  [ "$result" = "true" ]
  count=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  [ "$count" = "1" ]
}

@test "merge_guard_hook: existing PreToolUse entries are kept when hook is appended" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  count=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  [ "$count" = "2" ]
}

@test "merge_guard_hook: skips merge when hook is already present" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  count_after_first=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  merge_guard_hook
  count_after_second=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  [ "$count_after_first" = "$count_after_second" ]
}

# ── read_active_categories ────────────────────────────────────────────────────
# read_active_categories prints to stdout; capture with $() or process substitution.

@test "read_active_categories: always includes workflow" {
  mkdir -p "$TEST_DIR/.claude"
  echo "swift" > "$TEST_DIR/.claude/rules-sync.txt"
  cd "$TEST_DIR"
  result=$(read_active_categories)
  echo "$result" | grep -qx "workflow"
}

@test "read_active_categories: active categories appear in output" {
  mkdir -p "$TEST_DIR/.claude"
  printf 'swift\nvisionos\n' > "$TEST_DIR/.claude/rules-sync.txt"
  cd "$TEST_DIR"
  result=$(read_active_categories)
  echo "$result" | grep -qx "swift"
  echo "$result" | grep -qx "visionos"
}

@test "read_active_categories: commented-out categories are excluded" {
  mkdir -p "$TEST_DIR/.claude"
  printf 'swift\n# ios\nvisionos\n' > "$TEST_DIR/.claude/rules-sync.txt"
  cd "$TEST_DIR"
  result=$(read_active_categories)
  ! echo "$result" | grep -qx "ios"
}

@test "read_active_categories: no config file outputs only workflow" {
  mkdir -p "$TEST_DIR/.claude"
  cd "$TEST_DIR"
  # When no rules-sync.txt exists, output must contain only "workflow".
  # read_active_categories returns non-zero (file not found) so capture with || true.
  result=$(read_active_categories) || true
  [ "$result" = "workflow" ]
}

# ── pick_day non-interactive ──────────────────────────────────────────────────

@test "pick_day: non-interactive --day=Wednesday sets correct day and cron" {
  pick_day --day=Wednesday < /dev/null
  [ "$SELECTED_DAY_NAME" = "Wednesday" ]
  [ "$SELECTED_DAY_CRON" = "3" ]
}

@test "pick_day: non-interactive --day= is case-insensitive" {
  pick_day --day=wednesday < /dev/null
  [ "$SELECTED_DAY_NAME" = "Wednesday" ]
  [ "$SELECTED_DAY_CRON" = "3" ]
}

@test "pick_day: non-interactive unknown day defaults to Monday" {
  pick_day --day=Someday < /dev/null
  [ "$SELECTED_DAY_NAME" = "Monday" ]
  [ "$SELECTED_DAY_CRON" = "1" ]
}

@test "pick_day: non-interactive no flag defaults to Monday" {
  pick_day < /dev/null
  [ "$SELECTED_DAY_NAME" = "Monday" ]
  [ "$SELECTED_DAY_CRON" = "1" ]
}

# ── setup_directories ────────────────────────────────────────────────────────

@test "setup_directories: creates required directories" {
  cd "$TEST_DIR"
  setup_directories
  [ -d ".claude/rules/synced" ]
  [ -d ".github/workflows" ]
  [ -d ".claude/skills" ]
}

# ── write_rules_sync_config ───────────────────────────────────────────────────

@test "write_rules_sync_config: writes file with detected categories" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  write_rules_sync_config "swift ios"
  [ -f ".claude/rules-sync.txt" ]
  grep -qx "swift" ".claude/rules-sync.txt"
  grep -qx "ios" ".claude/rules-sync.txt"
}

@test "write_rules_sync_config: skips when file already exists" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  echo "existing" > ".claude/rules-sync.txt"
  write_rules_sync_config "swift ios"
  # File content must be unchanged and recorded as skipped
  grep -qx "existing" ".claude/rules-sync.txt"
  ! grep -q "swift" ".claude/rules-sync.txt"
  [[ "${SKIPPED_FILES[*]}" == *"rules-sync.txt"* ]]
}

@test "write_rules_sync_config: writes file with no categories when string is empty" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  write_rules_sync_config ""
  [ -f ".claude/rules-sync.txt" ]
  grep -q "# AI Guidelines Sync" ".claude/rules-sync.txt"
}

# ── cleanup_stale_rules ───────────────────────────────────────────────────────

@test "cleanup_stale_rules: removes category dirs not in active list" {
  cd "$TEST_DIR"
  mkdir -p ".claude/rules/synced/swift" ".claude/rules/synced/ios"
  cleanup_stale_rules "swift"
  [ -d ".claude/rules/synced/swift" ]
  [ ! -d ".claude/rules/synced/ios" ]
}

@test "cleanup_stale_rules: keeps all dirs when all are active" {
  cd "$TEST_DIR"
  mkdir -p ".claude/rules/synced/swift" ".claude/rules/synced/ios"
  cleanup_stale_rules "swift" "ios"
  [ -d ".claude/rules/synced/swift" ]
  [ -d ".claude/rules/synced/ios" ]
}

@test "cleanup_stale_rules: no-ops when synced dir does not exist" {
  cd "$TEST_DIR"
  cleanup_stale_rules "swift"
  [ ! -d ".claude/rules/synced" ]
}

@test "cleanup_stale_rules: removes all dirs when called with no active categories" {
  cd "$TEST_DIR"
  mkdir -p ".claude/rules/synced/swift" ".claude/rules/synced/ios"
  cleanup_stale_rules
  [ ! -d ".claude/rules/synced/swift" ]
  [ ! -d ".claude/rules/synced/ios" ]
}

# ── write_workflow_file ───────────────────────────────────────────────────────

@test "write_workflow_file: writes workflow file with correct cron value" {
  cd "$TEST_DIR"
  mkdir -p ".github/workflows"
  SELECTED_DAY_CRON=3
  SELECTED_DAY_NAME="Wednesday"
  write_workflow_file
  [ -f ".github/workflows/sync-claude-rules.yml" ]
  grep -q "0 9 \* \* 3" ".github/workflows/sync-claude-rules.yml"
  [[ "${WRITTEN_FILES[*]}" == *"Wednesday"* ]]
}

# ── write_skills_manifest ─────────────────────────────────────────────────────

@test "write_skills_manifest: writes sorted unique names" {
  cd "$TEST_DIR"
  mkdir -p ".claude/skills"
  write_skills_manifest "foo" "bar" "foo"
  [ -f ".claude/skills/.synced-manifest" ]
  result=$(cat ".claude/skills/.synced-manifest")
  [ "$result" = "$(printf 'bar\nfoo')" ]
  [[ "${WRITTEN_FILES[*]}" == *".synced-manifest"* ]]
}

@test "write_skills_manifest: no-op when called with no arguments" {
  cd "$TEST_DIR"
  mkdir -p ".claude/skills"
  write_skills_manifest
  [ ! -f ".claude/skills/.synced-manifest" ]
}

# ── migration ─────────────────────────────────────────────────────────────────

@test "migration: rules-sync renamed to rules-sync.txt preserving content" {
  cd "$TEST_DIR"
  git init -q
  mkdir -p ".claude"
  printf 'swift\nvisionos\n' > ".claude/rules-sync"
  checkout_default_and_pull() { return 0; }

  setup_project

  [ ! -f ".claude/rules-sync" ]
  [ -f ".claude/rules-sync.txt" ]
  grep -qx "swift" ".claude/rules-sync.txt"
  grep -qx "visionos" ".claude/rules-sync.txt"
}

# ── merge_gate_hooks ──────────────────────────────────────────────────────────

# Gate-hook fixtures: merge_gate_hooks wires an entry only if its script exists.
make_hook_files() {
  mkdir -p "$TEST_DIR/.claude/hooks/synced"
  local f
  for f in design-gate.sh protect-gate-integrity.sh design-fit-reminder.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/.claude/hooks/synced/$f"
  done
}

@test "merge_gate_hooks: wires two PreToolUse entries and one UserPromptSubmit" {
  mkdir -p "$TEST_DIR/.claude"
  make_hook_files
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  pre=$(jq '.hooks.PreToolUse | length' .claude/settings.json)
  ups=$(jq '.hooks.UserPromptSubmit | length' .claude/settings.json)
  [ "$pre" = "2" ]
  [ "$ups" = "1" ]
}

@test "merge_gate_hooks: idempotent on second run" {
  mkdir -p "$TEST_DIR/.claude"
  make_hook_files
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  before=$(jq -c '.hooks' .claude/settings.json)
  merge_gate_hooks
  after=$(jq -c '.hooks' .claude/settings.json)
  [ "$before" = "$after" ]
}

@test "merge_gate_hooks: coexists with merge_guard_hook entries" {
  mkdir -p "$TEST_DIR/.claude"
  make_hook_files
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  merge_gate_hooks
  pre=$(jq '.hooks.PreToolUse | length' .claude/settings.json)
  [ "$pre" = "3" ]
}

@test "merge_gate_hooks: commands reference CLAUDE_PROJECT_DIR literally" {
  mkdir -p "$TEST_DIR/.claude"
  make_hook_files
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)
  [[ "$cmd" == '${CLAUDE_PROJECT_DIR}/.claude/hooks/synced/design-gate.sh' ]]
}

# ── design-gate.sh guard ──────────────────────────────────────────────────────

# Work repo with an origin, a default branch, and a feature branch with one commit.
make_gated_repo() {
  git init -q --bare "$TEST_DIR/origin.git"
  git init -q "$TEST_DIR/work"
  cd "$TEST_DIR/work"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git branch -m main
  git remote add origin "$TEST_DIR/origin.git"
  git push -q origin main
  git fetch -q origin
  git checkout -q -b feature
  echo x > file.txt
  git add file.txt
  git -c user.email=t@t -c user.name=t commit -q -m change
  git push -q origin feature
  git fetch -q origin
}

gate_input() {
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$PWD" "$1"
}

@test "design-gate: unrelated bash command is allowed" {
  make_gated_repo
  run bash -c "echo '$(gate_input "git status")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 0 ]
}

@test "design-gate: gh pr create without a stamp is blocked" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: posting a PR review is NOT gated" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh api repos/o/r/pulls/80/reviews --input p.json")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 0 ]
}

@test "design-gate: gh api POST to pulls is blocked without a stamp" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh api repos/o/r/pulls -f title=x")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: valid PASS stamp with matching diff hash allows the PR" {
  make_gated_repo
  source "$SCRIPT_DIR/hooks/design-gate-common.sh"
  h=$(gate_diff_hash)
  mkdir -p .claude/design-gate
  jq -n --arg h "$h" '{verdict:"PASS",diff_hash:$h}' > .claude/design-gate/verdict.json
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 0 ]
}

@test "design-gate: stale stamp (branch changed after gate run) is blocked" {
  make_gated_repo
  source "$SCRIPT_DIR/hooks/design-gate-common.sh"
  h=$(gate_diff_hash)
  mkdir -p .claude/design-gate
  jq -n --arg h "$h" '{verdict:"PASS",diff_hash:$h}' > .claude/design-gate/verdict.json
  echo y >> file.txt
  git add file.txt
  git -c user.email=t@t -c user.name=t commit -q -m more
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: FAIL stamp is blocked" {
  make_gated_repo
  source "$SCRIPT_DIR/hooks/design-gate-common.sh"
  h=$(gate_diff_hash)
  mkdir -p .claude/design-gate
  jq -n --arg h "$h" '{verdict:"FAIL",diff_hash:$h}' > .claude/design-gate/verdict.json
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: human override allows without a stamp" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh pr create --fill")' | DESIGN_GATE_OVERRIDE=1 '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 0 ]
}

# ── protect-gate-integrity.sh ───────────────────────────────────────────────────

@test "protect-hooks: Write to a synced hook is blocked" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"/repo/.claude/hooks/synced/design-gate.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: Edit to settings.json is blocked" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"/repo/.claude/settings.json\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: bash tampering with the stamp is blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"echo x > .claude/design-gate/verdict.json\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: running the gate runner is allowed" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"bash .claude/hooks/synced/design-gate-run.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 0 ]
}

@test "protect-hooks: runner with model override is allowed" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"DESIGN_GATE_MODEL=sonnet bash .claude/hooks/synced/design-gate-run.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 0 ]
}

@test "protect-hooks: runner invocation with a trailing redirect is blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"bash .claude/hooks/synced/design-gate-run.sh > /dev/null; echo PASS > .claude/design-gate/verdict.json\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: unrelated command is allowed" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git status\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 0 ]
}

# ── design-fit-reminder.sh ────────────────────────────────────────────────────

@test "design-fit-reminder: exits 0 and prints the scope-check context" {
  run "$SCRIPT_DIR/hooks/design-fit-reminder.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Design fit:"* ]]
}

# ── regression tests from the pr-review-gate findings ─────────────────────────

@test "design-gate: gh -R flag before pr create is still gated" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh -R owner/repo pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: GraphQL createPullRequest mutation is gated" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh api graphql -f query=mutation_createPullRequest_x")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: gh api with method flag before pulls path is gated" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh api -X POST repos/o/r/pulls")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: unpushed local HEAD is blocked even with a valid stamp" {
  make_gated_repo
  echo z >> file.txt
  git add file.txt
  git -c user.email=t@t -c user.name=t commit -q -m local-only
  source "$SCRIPT_DIR/hooks/design-gate-common.sh"
  h=$(gate_diff_hash)
  mkdir -p .claude/design-gate
  jq -n --arg h "$h" '{verdict:"PASS",diff_hash:$h}' > .claude/design-gate/verdict.json
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: corrupt stamp JSON is blocked" {
  make_gated_repo
  mkdir -p .claude/design-gate
  echo 'not json' > .claude/design-gate/verdict.json
  run bash -c "echo '$(gate_input "gh pr create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: multi-line runner command with smuggled write is blocked" {
  printf '{"tool_input":{"command":"bash .claude/hooks/synced/design-gate-run.sh\\necho forged > .claude/design-gate/verdict.json"}}' > "$TEST_DIR/input.json"
  run bash -c "cat '$TEST_DIR/input.json' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: env prefix with command substitution is blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"DESIGN_GATE_MODEL=\$(id) bash .claude/hooks/synced/design-gate-run.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: quoted runner invocation is allowed" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"bash \\\".claude/hooks/synced/design-gate-run.sh\\\"\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 0 ]
}

@test "protect-hooks: removing the hooks container is blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"rm -rf .claude/hooks\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: split-prefix stamp write is blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"cd .claude && echo forged > design-gate/verdict.json\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: settings.local.json edit is blocked" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"/repo/.claude/settings.local.json\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "protect-hooks: NotebookEdit notebook_path on a hook is blocked" {
  run bash -c "echo '{\"tool_input\":{\"notebook_path\":\"/repo/.claude/hooks/synced/design-gate.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}

@test "merge_gate_hooks: not wired when hook files are absent" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  pre=$(jq '.hooks.PreToolUse // [] | length' .claude/settings.json)
  [ "$pre" = "0" ]
}

@test "merge_gate_hooks: wires entries and deny rules when hook files exist" {
  mkdir -p "$TEST_DIR/.claude/hooks/synced"
  for f in design-gate.sh protect-gate-integrity.sh design-fit-reminder.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/.claude/hooks/synced/$f"
  done
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  pre=$(jq '.hooks.PreToolUse | length' .claude/settings.json)
  deny=$(jq '.permissions.deny | length' .claude/settings.json)
  [ "$pre" = "2" ]
  [ "$deny" = "4" ]
}

@test "merge_gate_hooks: honors the hooks opt-out line" {
  mkdir -p "$TEST_DIR/.claude/hooks/synced"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/.claude/hooks/synced/design-gate.sh"
  printf 'swift\n# hooks\n' > "$TEST_DIR/.claude/rules-sync.txt"
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  pre=$(jq '.hooks.PreToolUse // [] | length' .claude/settings.json)
  [ "$pre" = "0" ]
}

@test "merge_gate_hooks: invalid settings.json reports failure, does not corrupt" {
  mkdir -p "$TEST_DIR/.claude/hooks/synced"
  for f in design-gate.sh protect-gate-integrity.sh design-fit-reminder.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/.claude/hooks/synced/$f"
  done
  echo 'not json' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_gate_hooks
  content=$(cat .claude/settings.json)
  [ "$content" = "not json" ]
}

# ── delta-review regressions (eac9e7e fixes) ──────────────────────────────────

@test "design-gate: double-space pr create is still gated" {
  make_gated_repo
  run bash -c "echo '$(gate_input "gh pr  create --fill")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: tab-separated pr create is still gated" {
  make_gated_repo
  printf '{"cwd":"%s","tool_input":{"command":"gh pr\\tcreate --fill"}}' "$PWD" > "$TEST_DIR/in.json"
  run bash -c "cat '$TEST_DIR/in.json' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 2 ]
}

@test "design-gate: git pull is allowed" {
  make_gated_repo
  run bash -c "echo '$(gate_input "git pull --ff-only")' | '$SCRIPT_DIR/hooks/design-gate.sh'"
  [ "$status" -eq 0 ]
}

@test "protect-hooks: git add of a synced hook is allowed (post-setup commit flow)" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git add .claude/hooks/synced/design-gate.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 0 ]
}

@test "protect-hooks: git checkout of a synced hook is still blocked" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git checkout -- .claude/hooks/synced/design-gate.sh\"}}' | '$SCRIPT_DIR/hooks/protect-gate-integrity.sh'"
  [ "$status" -eq 2 ]
}
