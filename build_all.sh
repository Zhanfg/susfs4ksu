#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN=0

if [ "${1:-}" = "--clean" ]; then
	CLEAN=1
	shift
fi

if [ "$#" -ne 0 ]; then
	echo "Usage: ./build_all.sh [--clean]" >&2
	exit 2
fi

args=()
if [ "$CLEAN" -eq 1 ]; then
	args+=(--clean)
fi

"$ROOT_DIR/build_ksu_susfs_tool.sh" "${args[@]}"
"$ROOT_DIR/build_ksu_module.sh"

echo "[+] SUSFS userspace + module build complete"
