---
paths:
  - setup.sh
  - tests/**
---

# setup.sh — shell scripting constraints

`setup.sh` targets bash 3.2 (macOS system bash). Active constraints:
- `set -uo pipefail` — **no** `set -e`
- Empty array + `set -u`: `"${arr[@]}"` aborts in bash 3.2 when the array is empty.
  Use `${arr[@]+"${arr[@]}"}` (established codebase pattern, see commit `f0f3fbc`)
- Guard early returns: `|| return 0` not `|| return` when absence means success
- BATS: a non-zero exit from a test body silently drops that test (shows as count
  mismatch `Executed N-1 instead of N`, not as `not ok`)
- Every claim of a write (`success …`, `WRITTEN_FILES+=`) sits in the success branch of the
  write it describes; a failed step is `fail_step <verb> <path>` + `return 1`, and
  `setup_project` calls each step with `|| return 1`. The output never names a write that did
  not happen, and a run that did not complete every step exits non-zero.
- Temp files are created beside their destination (`<path>$TMP_SUFFIX`, `mktemp` for a per-run
  name), staged in `UPSTREAM_STAGE` for the interrupt trap, and renamed over it; anything
  already at a sidecar or backup name — file or symlink — is a hard stop, never overwritten
  or followed. Output helpers print messages with `%s`, never `echo -e`.
- `.claude/settings.json`: the shape rule lives once in `JQ_SETTINGS_DEFS`; an unusable file is
  primed (projection), never refused — see the README ownership table.
