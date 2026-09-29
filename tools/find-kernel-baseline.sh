#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_TREE=""
PATCH_FILE="$ROOT_DIR/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch"
BEFORE="${SUSFS_BASELINE_BEFORE:-2026-09-27T00:00:00Z}"
AFTER="${SUSFS_BASELINE_AFTER:-2026-09-15T00:00:00Z}"

usage() {
	cat <<'EOF'
Usage:
  tools/find-kernel-baseline.sh --kernel-tree PATH [--patch PATH] [--before ISO] [--after ISO]

Scans first-parent history newest-to-oldest and prints the newest commit where
the complete kernel patch passes 'git apply --check'. The worktree is restored
to its original HEAD before exit.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--kernel-tree) KERNEL_TREE="$2"; shift 2 ;;
		--patch) PATCH_FILE="$2"; shift 2 ;;
		--before) BEFORE="$2"; shift 2 ;;
		--after) AFTER="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

[ -n "$KERNEL_TREE" ] || { echo "--kernel-tree is required" >&2; exit 2; }
[ -f "$PATCH_FILE" ] || { echo "patch not found: $PATCH_FILE" >&2; exit 1; }

ORIGINAL_HEAD="$(git -C "$KERNEL_TREE" rev-parse HEAD)"
trap 'git -C "$KERNEL_TREE" checkout -q "$ORIGINAL_HEAD" >/dev/null 2>&1 || true' EXIT

count=0
while IFS= read -r sha; do
	[ -n "$sha" ] || continue
	count=$((count + 1))
	git -C "$KERNEL_TREE" checkout -q "$sha"
	if git -C "$KERNEL_TREE" apply --check "$PATCH_FILE" >/dev/null 2>&1; then
		printf '%s\n' "$sha"
		printf '[+] compatible baseline found after %d candidate(s): %s\n' "$count" "$sha" >&2
		exit 0
	fi
done < <(
	git -C "$KERNEL_TREE" rev-list 		--first-parent 		--before="$BEFORE" 		--after="$AFTER" 		HEAD
)

echo "[-] no compatible first-parent commit found between $AFTER and $BEFORE" >&2
exit 1
