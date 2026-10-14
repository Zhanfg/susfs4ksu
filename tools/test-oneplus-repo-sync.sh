#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

WORKSPACE="$tmp/workspace"
REPO_BIN="$tmp/repo"
mkdir -p "$WORKSPACE"
cat > "$REPO_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[ ! -f "$TEST_COUNT" ] || count="$(cat "$TEST_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" > "$TEST_COUNT"
if [ "$TEST_MODE" = "transient" ] && [ "$count" -ge 3 ]; then
  exit 0
fi
exit 22
EOF
chmod +x "$REPO_BIN"
export TEST_COUNT="$tmp/attempts"
export TEST_MODE=transient
func="$(sed -n '/^sync_exact_repo_workspace() {/,/^}/p' \
  "$root/tools/oneplus13-workspace.sh")"
[ -n "$func" ]
eval "$func"
sleep() { :; }
sync_exact_repo_workspace
[ "$(cat "$TEST_COUNT")" = 3 ]
rm -f "$TEST_COUNT"
export TEST_MODE=permanent
if sync_exact_repo_workspace; then
  echo "ERROR: failed network sync was treated as success" >&2
  exit 1
fi
[ "$(cat "$TEST_COUNT")" = 3 ]
echo "PASS: retries transient failures, fails closed after bounded attempts"
