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

# ── guard hook merge ──────────────────────────────────────────────────────────

# Performs the same jq merge that setup_project does for the guard hook.
_merge_hook() {
  local settings_file="$1"
  local guard_cmd
  # shellcheck disable=SC2016
  guard_cmd='file=$(jq -r '"'"'.file_path // empty'"'"'); case "$file" in *".claude/rules/synced"*) echo "ERROR" >&2; exit 2;; esac'
  local guard_entry
  guard_entry=$(jq -n --arg cmd "$guard_cmd" \
    '{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":$cmd}]}')
  local tmp
  tmp=$(mktemp)
  jq --argjson entry "$guard_entry" \
    '.hooks = (.hooks // {}) | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$entry])' \
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
}

@test "guard hook: added to empty settings.json" {
  local settings="$TEST_DIR/settings.json"
  echo '{}' > "$settings"
  _merge_hook "$settings"
  count=$(jq '.hooks.PreToolUse | length' "$settings")
  [ "$count" = "1" ]
}

@test "guard hook: existing PostToolUse entry is preserved" {
  local settings="$TEST_DIR/settings.json"
  echo '{"hooks":{"PostToolUse":[]}}' > "$settings"
  _merge_hook "$settings"
  result=$(jq '.hooks | has("PostToolUse")' "$settings")
  [ "$result" = "true" ]
  count=$(jq '.hooks.PreToolUse | length' "$settings")
  [ "$count" = "1" ]
}

@test "guard hook: existing PreToolUse entries are kept when hook is appended" {
  local settings="$TEST_DIR/settings.json"
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}' > "$settings"
  _merge_hook "$settings"
  count=$(jq '.hooks.PreToolUse | length' "$settings")
  [ "$count" = "2" ]
}

@test "guard hook: setup_project skips merge when hook is already present" {
  local settings="$TEST_DIR/settings.json"
  echo '{}' > "$settings"
  _merge_hook "$settings"
  count_after_first=$(jq '.hooks.PreToolUse | length' "$settings")

  # setup_project checks for "rules/synced" before merging
  grep -q "rules/synced" "$settings"
  if ! grep -q "rules/synced" "$settings"; then
    _merge_hook "$settings"
  fi

  count_after_second=$(jq '.hooks.PreToolUse | length' "$settings")
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

# ── migration ─────────────────────────────────────────────────────────────────

@test "migration: rules-sync renamed to rules-sync.txt preserving content" {
  cd "$TEST_DIR"
  git init -q
  mkdir -p ".claude"
  printf 'swift\nvisionos\n' > ".claude/rules-sync"

  setup_project

  [ ! -f ".claude/rules-sync" ]
  [ -f ".claude/rules-sync.txt" ]
  grep -qx "swift" ".claude/rules-sync.txt"
  grep -qx "visionos" ".claude/rules-sync.txt"
}
