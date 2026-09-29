#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$ROOT_DIR/ksu_module_susfs"
OUT_FILE="${SUSFS_MODULE_OUTPUT:-$ROOT_DIR/ksu_module_susfs.zip}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"

usage() {
	cat <<'EOF'
Usage: ./build_ksu_module.sh [--output PATH]

Creates a deterministic module archive:
- stable file ordering
- normalized mtimes
- stripped ZIP extra fields

Set SOURCE_DATE_EPOCH to control the normalized timestamp.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--output)
			[ "$#" -ge 2 ] || { echo "missing value for --output" >&2; exit 2; }
			OUT_FILE="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "unknown argument: $1" >&2
			exit 2
			;;
	esac
done

command -v zip >/dev/null 2>&1 || {
	echo "[-] zip not found" >&2
	exit 1
}

[ -d "$MODULE_DIR" ] || {
	echo "[-] module directory missing: $MODULE_DIR" >&2
	exit 1
}

if [ -z "$SOURCE_DATE_EPOCH" ]; then
	SOURCE_DATE_EPOCH="$(git -C "$ROOT_DIR" log -1 --format=%ct 2>/dev/null || true)"
	SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1704067200}"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -a "$MODULE_DIR/." "$stage/"

# ZIP stores timestamps with a 1980 lower bound.
if command -v touch >/dev/null 2>&1; then
	find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} + 2>/dev/null || true
fi

tmp_zip="$OUT_FILE.tmp"
rm -f "$tmp_zip" "$OUT_FILE"

(
	cd "$stage"
	find . -type f -print | LC_ALL=C sort | zip -q -9 -X "$tmp_zip" -@
)

mv "$tmp_zip" "$OUT_FILE"
echo "[+] Module: $OUT_FILE"

if command -v sha256sum >/dev/null 2>&1; then
	sha256sum "$OUT_FILE"
fi
