#!/bin/bash
# Refreshes the derived copy of gate_default_branch inside setup.sh from its single
# authoritative representation in hooks/design-gate-common.sh (setup.sh must stay a
# self-contained curl-run file, so the knowledge is embedded at commit time and
# tests/setup.bats enforces byte-identity).
set -uo pipefail
cd "$(dirname "$0")/.."

fn_file=$(mktemp)
trap 'rm -f "$fn_file"' EXIT
awk '/^gate_default_branch\(\) \{/{f=1} f{print} f&&/^\}/{exit}' hooks/design-gate-common.sh > "$fn_file"
[ -s "$fn_file" ] || { echo "embed-common: extraction from design-gate-common.sh failed" >&2; exit 1; }

awk '
  NR==FNR { fn[++n]=$0; next }
  /^# >>> embedded-from: hooks\/design-gate-common\.sh/ { print; for (i=1;i<=n;i++) print fn[i]; skip=1; next }
  /^# <<< embedded-from: hooks\/design-gate-common\.sh/ { skip=0 }
  !skip { print }
' "$fn_file" setup.sh > setup.sh.tmp && mv setup.sh.tmp setup.sh
chmod +x setup.sh
echo "embed-common: setup.sh refreshed"
