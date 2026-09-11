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
  # Write-failure tests leave 555 directories; rm -rf on those fails and bats would
  # report the teardown error instead of the assertion that actually failed.
  chmod -R u+w "$TEST_DIR" 2>/dev/null
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

@test "merge_guard_hook: replaces an outdated guard instead of skipping it" {
  mkdir -p "$TEST_DIR/.claude"
  cat > "$TEST_DIR/.claude/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"file=$(jq -r '.file_path // empty'); case \"$file\" in *\".claude/rules/synced\"*) exit 2;; esac"}]}]}}
EOF
  cd "$TEST_DIR"
  merge_guard_hook
  count=$(jq '.hooks.PreToolUse | length' "$TEST_DIR/.claude/settings.json")
  [ "$count" = "1" ]
  cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$TEST_DIR/.claude/settings.json")
  [[ "$cmd" == *".tool_input.file_path"* ]]
}

@test "guard hook: blocks an edit under rules/synced given the real PreToolUse payload" {
  mkdir -p "$TEST_DIR/.claude"
  echo '{}' > "$TEST_DIR/.claude/settings.json"
  cd "$TEST_DIR"
  merge_guard_hook
  cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)
  run bash -c "$cmd" <<< '{"tool_name":"Edit","tool_input":{"file_path":"/r/.claude/rules/synced/x.md"}}'
  [ "$status" -eq 2 ]
  run bash -c "$cmd" <<< '{"tool_name":"Edit","tool_input":{"file_path":"/r/.claude/rules/local.md"}}'
  [ "$status" -eq 0 ]
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

# ── pilot-discovered setup.sh bugs ────────────────────────────────────────────

@test "checkout_default_and_pull: failed pull on a dirty tree proceeds instead of aborting" {
  git init -q --bare "$TEST_DIR/origin.git"
  git init -q "$TEST_DIR/work"
  cd "$TEST_DIR/work"
  echo a > tracked.txt
  git add tracked.txt
  git -c user.email=t@t -c user.name=t commit -q -m init
  git branch -m main
  git remote add origin "$TEST_DIR/origin.git"
  git push -q -u origin main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git config pull.rebase true
  echo dirty >> tracked.txt   # first-run-style unstaged change
  run checkout_default_and_pull
  [ "$status" -eq 0 ]
}

@test "checkout_default_and_pull: a clone behind its upstream whose pull fails is a hard stop" {
  git init -q --bare "$TEST_DIR/origin.git"
  git init -q "$TEST_DIR/seed"
  cd "$TEST_DIR/seed"
  echo a > tracked.txt
  git add tracked.txt
  git -c user.email=t@t -c user.name=t commit -q -m init
  git branch -m main
  git remote add origin "$TEST_DIR/origin.git"
  git push -q -u origin main
  git -C "$TEST_DIR/origin.git" symbolic-ref HEAD refs/heads/main   # not every git defaults to main
  git clone -q "$TEST_DIR/origin.git" "$TEST_DIR/work"
  echo b > tracked.txt                                   # remote moves on after the clone
  git -c user.email=t@t -c user.name=t commit -q -am second
  git push -q origin main
  cd "$TEST_DIR/work"
  git config pull.rebase true
  echo dirty >> tracked.txt                               # local unstaged change blocks the pull
  run checkout_default_and_pull
  [ "$status" -ne 0 ]
  [[ "$output" == *"behind"* ]]
  [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]   # nothing was forced
  grep -q dirty tracked.txt                                        # local work untouched
}

@test "checkout_default_and_pull: follows a default branch created on the remote after the clone" {
  git init -q --bare "$TEST_DIR/origin.git"
  git init -q "$TEST_DIR/seed"
  cd "$TEST_DIR/seed"
  echo a > tracked.txt
  git add tracked.txt
  git -c user.email=t@t -c user.name=t commit -q -m init
  git branch -m main
  git remote add origin "$TEST_DIR/origin.git"
  git push -q origin main
  git -C "$TEST_DIR/origin.git" symbolic-ref HEAD refs/heads/main       # not every git defaults to main
  git clone -q "$TEST_DIR/origin.git" "$TEST_DIR/work"                  # origin/HEAD -> main, no develop yet
  git branch develop
  git push -q origin develop
  git -C "$TEST_DIR/origin.git" symbolic-ref HEAD refs/heads/develop   # default moved after the clone
  cd "$TEST_DIR/work"
  run checkout_default_and_pull
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "develop" ]
  [ "$(git symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/develop" ]
}

@test "checkout_default_and_pull: keeps the cached origin/HEAD when the remote is unreachable" {
  git init -q "$TEST_DIR/work"
  cd "$TEST_DIR/work"
  echo a > tracked.txt
  git add tracked.txt
  git -c user.email=t@t -c user.name=t commit -q -m init
  git branch -m develop
  git remote add origin "$TEST_DIR/missing.git"
  git update-ref refs/remotes/origin/develop HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
  git checkout -q -b other
  run checkout_default_and_pull
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "develop" ]
}

# ── sync_upstream ─────────────────────────────────────────────────────────────

# Build a fake upstream archive and make curl serve it. Layout mirrors the real repo
# (top-level "<repo>-<sha>/" component, rules/<cat>/, skills/<name>/).
make_upstream_archive() {
  local root="$TEST_DIR/upstream/ai-guidelines-sync-abc123"
  mkdir -p "$root/rules/workflow" "$root/rules/swift" "$root/skills/shared-skill"
  printf 'body\n' > "$root/rules/workflow/a.md"
  printf 'swift rule\n' > "$root/rules/swift/s.md"
  printf 'skill\n' > "$root/skills/shared-skill/SKILL.md"
  mkdir -p "$root/skills/shared-skill/sub"
  printf 'sub\n' > "$root/skills/shared-skill/sub/a.md"
  mkdir -p "$root/keep" "$root/rules/bad name"          # bait for the traversal test
  printf 'upstream\n' > "$root/keep/k.md"
  printf 'x\n' > "$root/rules/bad name/b.md"
  tar -czf "$TEST_DIR/upstream.tgz" -C "$TEST_DIR/upstream" ai-guidelines-sync-abc123
  curl() { cat "$TEST_DIR/upstream.tgz"; }
  stub_mktemp
}

# Make the extraction dir a known path so tests can assert it is gone afterwards.
stub_mktemp() {
  mktemp() { mkdir -p "$TEST_DIR/extract"; echo "$TEST_DIR/extract"; }
}

@test "sync_upstream: copies upstream files byte-identical, trailing newline included" {
  make_upstream_archive
  cd "$TEST_DIR"
  sync_upstream workflow
  cmp -s ".claude/rules/synced/workflow/a.md" "$TEST_DIR/upstream/ai-guidelines-sync-abc123/rules/workflow/a.md"
  [ "$(od -An -c .claude/rules/synced/workflow/a.md | tr -d ' ')" = 'body\n' ]
  [ ! -e "$TEST_DIR/extract" ]
  [ ! -e ".claude/rules/synced/workflow.new" ]
}

@test "sync_upstream: only active categories are written" {
  make_upstream_archive
  cd "$TEST_DIR"
  sync_upstream workflow
  [ -f ".claude/rules/synced/workflow/a.md" ]
  [ ! -e ".claude/rules/synced/swift" ]
}

@test "sync_upstream: an active category becomes exactly the upstream category" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/rules/synced/workflow
  echo stale > .claude/rules/synced/workflow/removed-upstream.md
  sync_upstream workflow
  [ -f ".claude/rules/synced/workflow/a.md" ]
  [ ! -e ".claude/rules/synced/workflow/removed-upstream.md" ]
}

@test "sync_upstream: skills are overlaid, local skills kept, manifest lists upstream names" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/local-skill
  echo mine > .claude/skills/local-skill/SKILL.md
  sync_upstream workflow
  [ -f ".claude/skills/shared-skill/SKILL.md" ]
  [ "$(cat .claude/skills/local-skill/SKILL.md)" = "mine" ]
  [ "$(cat .claude/skills/.synced-manifest)" = "shared-skill" ]
}

@test "sync_upstream: a failed download writes nothing and leaves no temp dir" {
  cd "$TEST_DIR"
  stub_mktemp
  curl() { return 22; }
  sync_upstream workflow
  [ ! -e ".claude/rules/synced" ]
  [ ! -e ".claude/skills" ]
  [ ! -e "$TEST_DIR/extract" ]
}

@test "sync_upstream: a corrupt archive writes nothing and leaves no temp dir" {
  cd "$TEST_DIR"
  stub_mktemp
  curl() { echo "not a tarball"; }
  sync_upstream workflow
  [ ! -e ".claude/rules/synced" ]
  [ ! -e "$TEST_DIR/extract" ]
}

@test "sync_upstream: a category name that is not a bare directory name is never used as a path" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/rules/keep
  echo mine > .claude/rules/keep/k.md
  # "../keep" resolves to an existing upstream dir (rules/../keep) and to an existing local
  # dir (.claude/rules/synced/../keep): without the guard it would be replaced wholesale.
  sync_upstream workflow ".." "../keep" "bad name" ""
  [ "$(cat .claude/rules/keep/k.md)" = "mine" ]
  [ ! -e ".claude/rules/synced/bad name" ]
  [ ! -e ".claude/rules/rules" ]
  [ "$(find .claude -name '*.new' -o -name '*.old' -o -name '*.tmp' | wc -l | tr -d ' ')" = "0" ]
  [ -f ".claude/rules/synced/workflow/a.md" ]
}

# cp that fails for one destination path (last argument) and works everywhere else.
fail_cp_for() {
  local pattern="$1"
  eval "cp() { case \"\${*: -1}\" in $pattern) return 1 ;; esac; command cp \"\$@\"; }"
}

@test "sync_upstream: a skill that fails to install is not recorded in the manifest" {
  make_upstream_archive
  cd "$TEST_DIR"
  fail_cp_for '*shared-skill/SKILL.md.ai-guidelines-sync.tmp'
  sync_upstream workflow
  [ ! -e ".claude/skills/.synced-manifest" ]
  [ ! -e ".claude/skills/shared-skill" ]
  [ "$(find .claude -name '*.tmp' | wc -l | tr -d ' ')" = "0" ]
  [ -f ".claude/rules/synced/workflow/a.md" ]   # categories unaffected
}

@test "sync_upstream: a skill whose later file fails is rolled back, not left half-installed" {
  make_upstream_archive
  cd "$TEST_DIR"
  fail_cp_for '*shared-skill/sub/a.md.ai-guidelines-sync.tmp'      # SKILL.md sorts first and would already be installed
  sync_upstream workflow
  [ ! -e ".claude/skills/shared-skill" ]
  [ ! -e ".claude/skills/.synced-manifest" ]
  [ "${#WRITTEN_FILES[@]}" -gt 0 ]
  for w in "${WRITTEN_FILES[@]}"; do [[ "$w" != *shared-skill* ]]; done
}

@test "sync_upstream: a skill overlaid onto an existing local dir is rolled back to only its own files" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local > .claude/skills/shared-skill/notes.md
  fail_cp_for '*shared-skill/sub/a.md.ai-guidelines-sync.tmp'
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/notes.md)" = "local" ]
  [ ! -e ".claude/skills/shared-skill/SKILL.md" ]
  [ ! -e ".claude/skills/shared-skill/sub" ]                 # dir created by the failed run is pruned
  [ ! -e ".claude/skills/.synced-manifest" ]
}

@test "sync_upstream: a rolled-back overlay restores the local file it had replaced" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local-version > .claude/skills/shared-skill/SKILL.md   # same name as upstream
  fail_cp_for '*shared-skill/sub/a.md.ai-guidelines-sync.tmp'
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "local-version" ]
  [ "$(find .claude -name '*.bak' -o -name '*.tmp' | wc -l | tr -d ' ')" = "0" ]
}

@test "sync_upstream: a copy failure on the path that has local content leaves that content untouched" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local-version > .claude/skills/shared-skill/SKILL.md
  fail_cp_for '*shared-skill/SKILL.md.ai-guidelines-sync.tmp'   # fails before any move
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "local-version" ]
  [ ! -e ".claude/skills/shared-skill/sub" ]
  [ ! -e ".claude/skills/.synced-manifest" ]
}

@test "sync_upstream: a stray sidecar next to a local file makes the skill fail without touching the file" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local-version > .claude/skills/shared-skill/SKILL.md
  echo old-backup > ".claude/skills/shared-skill/SKILL.md$UPSTREAM_BAK_SUFFIX"
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "local-version" ]
  [ "$(cat ".claude/skills/shared-skill/SKILL.md$UPSTREAM_BAK_SUFFIX")" = "old-backup" ]
  [ ! -e ".claude/skills/.synced-manifest" ]
}

@test "sync_upstream: a failed backup move leaves the local file untouched after rollback" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local-version > .claude/skills/shared-skill/SKILL.md
  mv() { case "${*: -1}" in *"$UPSTREAM_BAK_SUFFIX") return 1 ;; esac; command mv "$@"; }
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "local-version" ]
  [ ! -e ".claude/skills/shared-skill/sub" ]
  [ ! -e ".claude/skills/.synced-manifest" ]
  [ "$(find .claude -name '*.ai-guidelines-sync.*' | wc -l | tr -d ' ')" = "0" ]
}

@test "sync_upstream: a successful overlay replaces a same-named local file and leaves no backup" {
  make_upstream_archive
  cd "$TEST_DIR"
  mkdir -p .claude/skills/shared-skill
  echo local-version > .claude/skills/shared-skill/SKILL.md
  sync_upstream workflow
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "skill" ]
  [ "$(find .claude -name '*.bak' | wc -l | tr -d ' ')" = "0" ]
  [ "$(cat .claude/skills/.synced-manifest)" = "shared-skill" ]
}

@test "replace_dir: a pending swap from a failed restore is settled before the next category" {
  cd "$TEST_DIR"
  mkdir -p src/swift .claude/rules/synced/workflow.old
  echo s > src/swift/s.md
  echo old > .claude/rules/synced/workflow.old/a.md
  UPSTREAM_SWAP_OLD=".claude/rules/synced/workflow.old"      # as left by an unrestorable swap
  UPSTREAM_SWAP_DEST=".claude/rules/synced/workflow"
  replace_dir src/swift .claude/rules/synced/swift
  [ "$(cat .claude/rules/synced/workflow/a.md)" = "old" ]    # restored, not clobbered
  [ ! -e ".claude/rules/synced/workflow.old" ]
  [ -f ".claude/rules/synced/swift/s.md" ]
  [ -z "$UPSTREAM_SWAP_OLD" ]
}

@test "cleanup_upstream_tmp: rolls back the skill overlay that was in flight" {
  cd "$TEST_DIR"
  mkdir -p src/sub .claude/skills/shared-skill
  echo local > .claude/skills/shared-skill/SKILL.md
  echo notes > .claude/skills/shared-skill/notes.md
  echo up > src/SKILL.md; echo up > src/sub/a.md
  # Simulate an interrupt after two files were installed and before the overlay finished.
  UPSTREAM_SKILL_DEST=".claude/skills/shared-skill"; UPSTREAM_SKILL_CREATED=false
  install_file src/SKILL.md .claude/skills/shared-skill/SKILL.md
  install_file src/sub/a.md .claude/skills/shared-skill/sub/a.md
  cleanup_upstream_tmp
  [ "$(cat .claude/skills/shared-skill/SKILL.md)" = "local" ]
  [ "$(cat .claude/skills/shared-skill/notes.md)" = "notes" ]
  [ ! -e ".claude/skills/shared-skill/sub" ]
  [ "$(find .claude -name '*.ai-guidelines-sync.*' | wc -l | tr -d ' ')" = "0" ]
}

@test "cleanup_upstream_tmp: removes a skill dir the interrupted run had created" {
  cd "$TEST_DIR"
  mkdir -p src
  echo up > src/SKILL.md
  UPSTREAM_SKILL_DEST=".claude/skills/new-skill"; UPSTREAM_SKILL_CREATED=true
  install_file src/SKILL.md .claude/skills/new-skill/SKILL.md
  cleanup_upstream_tmp
  [ ! -e ".claude/skills/new-skill" ]
}

@test "install_file: never overwrites a local file sitting at a sidecar name" {
  cd "$TEST_DIR"
  echo x > src.txt
  echo precious > "dest.txt$UPSTREAM_BAK_SUFFIX"
  run install_file src.txt dest.txt
  [ "$status" -ne 0 ]
  [ ! -e dest.txt ]
  [ "$(cat "dest.txt$UPSTREAM_BAK_SUFFIX")" = "precious" ]
}

@test "settle_swap: a failed restore warns with both paths and leaves the old copy in place" {
  cd "$TEST_DIR"
  mkdir -p .claude/rules/synced/workflow.old
  UPSTREAM_SWAP_OLD=".claude/rules/synced/workflow.old"; UPSTREAM_SWAP_DEST=".claude/rules/synced/workflow"
  mv() { return 1; }
  run settle_swap
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflow.old"* ]]
  [[ "$output" == *"by hand"* ]]
  [ -d ".claude/rules/synced/workflow.old" ]
}

@test "install_file: refuses a destination that is a directory" {
  cd "$TEST_DIR"
  echo x > src.txt
  mkdir -p dest.d
  run install_file src.txt dest.d
  [ "$status" -ne 0 ]
  [ "$(find . -name '*.ai-guidelines-sync.*' | wc -l | tr -d ' ')" = "0" ]
}

@test "cleanup_upstream_tmp: restores a category whose swap was interrupted" {
  cd "$TEST_DIR"
  mkdir -p .claude/rules/synced/workflow.old .claude/rules/synced/workflow.new
  echo old > .claude/rules/synced/workflow.old/a.md
  UPSTREAM_SWAP_OLD=".claude/rules/synced/workflow.old"
  UPSTREAM_SWAP_DEST=".claude/rules/synced/workflow"
  UPSTREAM_STAGE=".claude/rules/synced/workflow.new"
  cleanup_upstream_tmp
  [ "$(cat .claude/rules/synced/workflow/a.md)" = "old" ]
  [ ! -e ".claude/rules/synced/workflow.old" ]
  [ ! -e ".claude/rules/synced/workflow.new" ]
}

@test "read_active_categories: trims whitespace and refuses names that are not bare directory names" {
  cd "$TEST_DIR"
  mkdir -p .claude
  printf '  swift  \n../skills\n..\nios/../mac\n\t\nxcode\n' > .claude/rules-sync.txt
  result=$(read_active_categories 2>/dev/null)
  [ "$result" = "$(printf 'workflow\nswift\nxcode')" ]
}

# ── output never claims a write that did not happen ──────────────────────────
# A 555 directory blocks creating a file but not overwriting an existing owner-writable
# one, so these tests never pre-create the target. Arrays are asserted with ${#arr[@]}:
# "${arr[*]}" on an empty array aborts under set -u on bash 3.2 and drops the test.

@test "write_workflow_file: a failed write is an error and is not reported as written" {
  cd "$TEST_DIR"
  mkdir -p ".github/workflows"
  chmod 555 ".github/workflows"
  status=0
  write_workflow_file || status=$?
  [ "$status" -ne 0 ]
  [ ! -e ".github/workflows/sync-claude-rules.yml" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "write_rules_sync_config: a failed write is an error and is not reported as written" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  chmod 555 ".claude"
  status=0
  write_rules_sync_config "swift" || status=$?
  [ "$status" -ne 0 ]
  [ ! -e ".claude/rules-sync.txt" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "write_skills_manifest: a failed write is an error and is not reported as written" {
  cd "$TEST_DIR"
  mkdir -p ".claude/skills"
  chmod 555 ".claude/skills"
  status=0
  write_skills_manifest "foo" || status=$?
  [ "$status" -ne 0 ]
  [ ! -e ".claude/skills/.synced-manifest" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "sync_upstream: a manifest that cannot be written fails the sync" {
  make_upstream_archive
  cd "$TEST_DIR"
  write_skills_manifest() { return 1; }
  status=0
  sync_upstream workflow || status=$?
  [ "$status" -ne 0 ]
}

@test "migrate_legacy_files: a failed rename is an error and prints no success line" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  printf 'swift\n' > ".claude/rules-sync"
  chmod 555 ".claude"
  run migrate_legacy_files
  [ "$status" -ne 0 ]
  [[ "$output" != *"Renamed"* ]]
  [ -f ".claude/rules-sync" ]
}

@test "cleanup_stale_rules: a failed removal is an error and prints no success line" {
  cd "$TEST_DIR"
  mkdir -p ".claude/rules/synced/stale"
  chmod 555 ".claude/rules/synced"
  run cleanup_stale_rules workflow
  [ "$status" -ne 0 ]
  [[ "$output" != *"Removed stale"* ]]
  [ -d ".claude/rules/synced/stale" ]
}

# ── settings.json priming ────────────────────────────────────────────────────
# `warn` writes to stdout, so direct calls redirect stdout to a file in the same shell
# (arrays stay visible) and assert the stable token "primed", never the glyph.
# Fixture loops fail through `|| { echo "<fixture>: <what>"; false; }` so the fixture is named.

write_settings() { mkdir -p ".claude"; printf '%s' "$1" > ".claude/settings.json"; }
current_guard_settings() {
  write_settings '{}'
  merge_guard_hook >/dev/null
  WRITTEN_FILES=(); SKIPPED_FILES=()
}
guard_count() { jq '[.hooks.PreToolUse[]?.hooks[]?.command // "" | select(test("tool_input.file_path"))] | length' "$1"; }
root_without_hooks() { jq -c -S 'del(.hooks)' "$1"; }
hooks_without_pretooluse() { jq -c -S '.hooks | if type == "object" then del(.PreToolUse) else {} end' "$1"; }

FIXTURE_BARE_ENTRY='{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"file=$(jq -r .file_path) rules/synced"}]}'
FIXTURE_PERMISSIONS_HOOKS_ARRAY='{"permissions":{"allow":["Bash"]},"hooks":[]}'
FIXTURE_PRETOOLUSE_OBJECT='{"hooks":{"PreToolUse":{"a":1},"PostToolUse":[]}}'
FIXTURE_FOREIGN_ENTRIES='{"hooks":{"PreToolUse":[{"matcher":"Bash"},{"matcher":"X","hooks":null},{"matcher":"Y","hooks":[{"type":"command","command":null}]}]}}'
FIXTURE_OUTDATED_GUARD='{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"file=$(jq -r .file_path); case $file in *rules/synced*) exit 2;; esac"}]}]}}'

assert_primed_ok() {   # $1 = path of the original copy
  [ "$status" -eq 0 ]
  settings_json_usable ".claude/settings.json"
  [ "$(guard_count .claude/settings.json)" = "1" ]
  grep -q primed "$TEST_DIR/out"
  [[ "${WRITTEN_FILES[*]}" == *primed* ]]
  [ "${#SKIPPED_FILES[@]}" -eq 0 ]
  cmp -s ".claude/settings.json.before-priming" "$1"
}

@test "merge_guard_hook: a bare hook entry at the root is primed — root keys kept, guard added" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_BARE_ENTRY"
  cp ".claude/settings.json" "$TEST_DIR/orig"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  assert_primed_ok "$TEST_DIR/orig"
  [ "$(root_without_hooks .claude/settings.json)" = "$(root_without_hooks "$TEST_DIR/orig")" ]
  [ "$(jq -r .matcher .claude/settings.json)" = "Edit|Write|MultiEdit" ]
}

@test "merge_guard_hook: a broken hooks key beside real settings is primed — settings survive" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_PERMISSIONS_HOOKS_ARRAY"
  cp ".claude/settings.json" "$TEST_DIR/orig"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  assert_primed_ok "$TEST_DIR/orig"
  [ "$(root_without_hooks .claude/settings.json)" = "$(root_without_hooks "$TEST_DIR/orig")" ]
  [ "$(jq -r '.permissions.allow[0]' .claude/settings.json)" = "Bash" ]
}

@test "merge_guard_hook: a PreToolUse object is primed, not silently coerced — other events survive" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_PRETOOLUSE_OBJECT"
  cp ".claude/settings.json" "$TEST_DIR/orig"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  assert_primed_ok "$TEST_DIR/orig"
  [ "$(hooks_without_pretooluse .claude/settings.json)" = "$(hooks_without_pretooluse "$TEST_DIR/orig")" ]
  [ "$(jq '.hooks.PreToolUse | length' .claude/settings.json)" = "1" ]
  [ "$(jq -c '.hooks.PostToolUse' .claude/settings.json)" = "[]" ]
}

@test "merge_guard_hook: a primed document is always written, never reported as already present" {
  cd "$TEST_DIR"
  current_guard_settings
  jq '.hooks.PreToolUse += ["junk"]' ".claude/settings.json" > "$TEST_DIR/junk" && mv "$TEST_DIR/junk" ".claude/settings.json"
  cp ".claude/settings.json" "$TEST_DIR/orig"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  assert_primed_ok "$TEST_DIR/orig"
  [ "$(jq '.hooks.PreToolUse | length' .claude/settings.json)" = "1" ]
}

@test "merge_guard_hook: a usable file is not primed and prints no warning" {
  cd "$TEST_DIR"
  write_settings '{"permissions":{"allow":["Bash"]},"hooks":{"PostToolUse":[]}}'
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -eq 0 ]
  ! grep -q primed "$TEST_DIR/out"
  [ ! -e ".claude/settings.json.before-priming" ]
  [ "$(jq -r '.permissions.allow[0]' .claude/settings.json)" = "Bash" ]
  [ "$(guard_count .claude/settings.json)" = "1" ]
}

# settings_json_usable — one test per alphabet member

@test "settings_json_usable: {} is usable" { cd "$TEST_DIR"; write_settings '{}'; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: hooks null is usable" { cd "$TEST_DIR"; write_settings '{"hooks":null}'; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: other hook events are usable" { cd "$TEST_DIR"; write_settings '{"hooks":{"PostToolUse":[]}}'; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: foreign PreToolUse entries with absent or null parts are usable" { cd "$TEST_DIR"; write_settings "$FIXTURE_FOREIGN_ENTRIES"; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: an outdated guard is usable" { cd "$TEST_DIR"; write_settings "$FIXTURE_OUTDATED_GUARD"; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: the current guard is usable" { cd "$TEST_DIR"; current_guard_settings; run settings_json_usable .claude/settings.json; [ "$status" -eq 0 ]; }
@test "settings_json_usable: a bare hook entry at the root is not usable" { cd "$TEST_DIR"; write_settings "$FIXTURE_BARE_ENTRY"; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: hooks as an array is not usable" { cd "$TEST_DIR"; write_settings "$FIXTURE_PERMISSIONS_HOOKS_ARRAY"; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: PreToolUse as an object is not usable" { cd "$TEST_DIR"; write_settings "$FIXTURE_PRETOOLUSE_OBJECT"; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: a null root is not usable" { cd "$TEST_DIR"; write_settings 'null'; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: invalid JSON is not usable" { cd "$TEST_DIR"; write_settings '{"hooks":'; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: a 0-byte file is not usable" { cd "$TEST_DIR"; write_settings ''; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: a whitespace-only file is not usable" { cd "$TEST_DIR"; write_settings '  '; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: two documents are not usable even when the first is valid" { cd "$TEST_DIR"; write_settings '{"hooks":{}}
{"b":2}'; run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]; }
@test "settings_json_usable: a malformed entry beside the current guard is not usable" {
  cd "$TEST_DIR"; current_guard_settings
  jq '.hooks.PreToolUse += ["junk"]' ".claude/settings.json" > "$TEST_DIR/junk" && mv "$TEST_DIR/junk" ".claude/settings.json"
  run settings_json_usable .claude/settings.json; [ "$status" -eq 1 ]
}

# project_settings_document — the projection is the identity on usable input, closed and idempotent on the rest

@test "project_settings_document: identity on every usable document" {
  cd "$TEST_DIR"
  local doc
  for doc in '{}' '{"hooks":null}' '{"hooks":{"PostToolUse":[]}}' "$FIXTURE_FOREIGN_ENTRIES" "$FIXTURE_OUTDATED_GUARD"; do
    write_settings "$doc"
    [ "$(project_settings_document .claude/settings.json | jq -c -S .)" = "$(jq -c -S . .claude/settings.json)" ] \
      || { echo "fixture $doc: projection is not the identity"; false; }
  done
}

@test "project_settings_document: every unusable document projects to a usable, idempotent one" {
  cd "$TEST_DIR"
  local doc projected
  for doc in "$FIXTURE_BARE_ENTRY" "$FIXTURE_PERMISSIONS_HOOKS_ARRAY" "$FIXTURE_PRETOOLUSE_OBJECT" 'null' '[1]' '{"hooks":{"PreToolUse":[{"matcher":"ok"},"junk",{"matcher":"bad","hooks":[{"command":7}]}]}}'; do
    write_settings "$doc"
    projected=$(project_settings_document .claude/settings.json)
    printf '%s' "$projected" > "$TEST_DIR/projected"
    settings_json_usable "$TEST_DIR/projected" || { echo "fixture $doc: not usable after projection"; false; }
    [ "$(project_settings_document "$TEST_DIR/projected" | jq -c -S .)" = "$(printf '%s' "$projected" | jq -c -S .)" ] \
      || { echo "fixture $doc: projection is not idempotent"; false; }
  done
}

@test "project_settings_document: unparsable, empty, whitespace and multi-document inputs project to {}" {
  cd "$TEST_DIR"
  local doc
  for doc in '{"hooks":' '' '  ' '{"a":1}
{"b":2}'; do
    write_settings "$doc"
    [ "$(project_settings_document .claude/settings.json | jq -c -S .)" = "{}" ] \
      || { echo "fixture [$doc]: did not project to {}"; false; }
  done
}

# environmental failures stay hard stops, gated like any write

@test "merge_guard_hook: an unwritable directory is an error with nothing reported and no sidecar" {
  cd "$TEST_DIR"
  write_settings '{}'
  chmod 555 ".claude"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -ne 0 ]
  [ "$(cat .claude/settings.json)" = "{}" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
  [ "${#SKIPPED_FILES[@]}" -eq 0 ]
  [ "$(find .claude -name '*.ai-guidelines-sync.tmp*' | wc -l | tr -d ' ')" = "0" ]
}

@test "merge_guard_hook: creating a missing settings.json in an unwritable directory is an error" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  chmod 555 ".claude"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -ne 0 ]
  [ ! -e ".claude/settings.json" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "merge_guard_hook: a live symlink named settings.json is an error and its target is untouched" {
  cd "$TEST_DIR"
  mkdir -p ".claude" "$TEST_DIR/outside"
  printf 'secret' > "$TEST_DIR/outside/target"
  ln -s "$TEST_DIR/outside/target" ".claude/settings.json"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_DIR/outside/target")" = "secret" ]
  [ -L ".claude/settings.json" ]
  [ ! -e "$TEST_DIR/outside/target.before-priming" ]
}

@test "merge_guard_hook: a dangling symlink at the backup name is refused and nothing is created" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_BARE_ENTRY"
  ln -s "$TEST_DIR/planted" ".claude/settings.json.before-priming"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_DIR/planted" ]
  [ "$(cat .claude/settings.json)" = "$FIXTURE_BARE_ENTRY" ]
}

@test "merge_guard_hook: an existing backup is refused rather than overwritten" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_BARE_ENTRY"
  printf 'earlier original' > ".claude/settings.json.before-priming"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ "$(cat .claude/settings.json.before-priming)" = "earlier original" ]
  [ "$(cat .claude/settings.json)" = "$FIXTURE_BARE_ENTRY" ]
}

@test "merge_guard_hook: an empty projection is an error, not an empty settings.json" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_BARE_ENTRY"
  project_settings_document() { :; }
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -ne 0 ]
  [ "$(cat .claude/settings.json)" = "$FIXTURE_BARE_ENTRY" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "merge_guard_hook: a failed rename leaves no sidecar and clears the interrupt-trap stage" {
  cd "$TEST_DIR"
  write_settings '{}'
  mv() { return 1; }
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -ne 0 ]
  [ "$(find .claude -name '*.ai-guidelines-sync.tmp*' | wc -l | tr -d ' ')" = "0" ]
  [ -z "$UPSTREAM_STAGE" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}

@test "cleanup_upstream_tmp: removes a settings sidecar the interrupted run had staged" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  : > ".claude/settings.json.ai-guidelines-sync.tmp.abc123"
  UPSTREAM_STAGE=".claude/settings.json.ai-guidelines-sync.tmp.abc123"
  cleanup_upstream_tmp
  [ ! -e ".claude/settings.json.ai-guidelines-sync.tmp.abc123" ]
}

@test "migrate_legacy_files: a failed deprecated-skill removal is an error and prints no success line" {
  cd "$TEST_DIR"
  mkdir -p ".claude/skills/setup-project-ai"
  chmod 555 ".claude/skills"
  run migrate_legacy_files
  [ "$status" -ne 0 ]
  [[ "$output" != *"Removed deprecated"* ]]
  [ -d ".claude/skills/setup-project-ai" ]
}

@test "output helpers: a message is printed verbatim, escape sequences are not decoded" {
  run err 'name\033[0m tail'
  [[ "$output" == *'name\033[0m tail'* ]]
  run success 'a\tb'
  [[ "$output" == *'a\tb'* ]]
}

@test "install_file: a dangling symlink at a sidecar name is refused" {
  cd "$TEST_DIR"
  mkdir -p "skills/s"
  printf 'x' > "$TEST_DIR/src"
  ln -s "$TEST_DIR/planted" "skills/s/f.md.ai-guidelines-sync.tmp"
  run install_file "$TEST_DIR/src" "skills/s/f.md"
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_DIR/planted" ]
  [ ! -e "skills/s/f.md" ]
}

@test "merge_guard_hook: a directory named settings.json is an error" {
  cd "$TEST_DIR"
  mkdir -p ".claude/settings.json"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ -d ".claude/settings.json" ]
}

@test "merge_guard_hook: a dangling symlink is an error and its target is not created" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  ln -s "nowhere" ".claude/settings.json"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ ! -e ".claude/nowhere" ]
}

@test "merge_guard_hook: a stray sidecar next to settings.json is an error and the file is untouched" {
  cd "$TEST_DIR"
  write_settings '{}'
  : > ".claude/settings.json.ai-guidelines-sync.tmp.stale"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ "$(cat .claude/settings.json)" = "{}" ]
}

@test "merge_guard_hook: a stray sidecar is refused before settings.json would be created" {
  cd "$TEST_DIR"
  mkdir -p ".claude"
  : > ".claude/settings.json.ai-guidelines-sync.tmp.stale"
  run merge_guard_hook
  [ "$status" -ne 0 ]
  [ ! -e ".claude/settings.json" ]
}

@test "merge_guard_hook: an unusable file whose backup cannot be written is an error before any change" {
  cd "$TEST_DIR"
  write_settings "$FIXTURE_BARE_ENTRY"
  chmod 555 ".claude"
  status=0
  merge_guard_hook > "$TEST_DIR/out" || status=$?
  [ "$status" -ne 0 ]
  [ "$(cat .claude/settings.json)" = "$FIXTURE_BARE_ENTRY" ]
  [ ! -e ".claude/settings.json.before-priming" ]
  [ "${#WRITTEN_FILES[@]}" -eq 0 ]
}
