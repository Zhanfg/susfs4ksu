#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$ROOT_DIR/ksu_susfs"
BUILD_ROOT="${SUSFS_BUILD_DIR:-$PROJECT_DIR/.build}"
OBJ_DIR="$BUILD_ROOT/obj"
LIBS_DIR="$BUILD_ROOT/libs"
OUTPUT="${SUSFS_TOOL_OUTPUT:-$BUILD_ROOT/dist/ksu_susfs_arm64}"
JOBS="${JOBS:-}"

usage() {
	cat <<'EOF'
Usage: ./build_ksu_susfs_tool.sh [--clean] [--jobs N] [--output PATH]

Incremental build is the default. Object files and standalone build outputs stay
under ksu_susfs/.build so compiling never modifies tracked module sources.

Environment:
  ANDROID_NDK_HOME / NDK_HOME   preferred pinned NDK root
  SUSFS_BUILD_DIR               override incremental build directory
  SUSFS_TOOL_OUTPUT             override output binary
  JOBS                          parallel build jobs
EOF
}

CLEAN=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--clean)
			CLEAN=1
			shift
			;;
		--jobs)
			[ "$#" -ge 2 ] || { echo "missing value for --jobs" >&2; exit 2; }
			JOBS="$2"
			shift 2
			;;
		--output)
			[ "$#" -ge 2 ] || { echo "missing value for --output" >&2; exit 2; }
			OUTPUT="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

find_ndk_build() {
	if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -x "$ANDROID_NDK_HOME/ndk-build" ]; then
		printf '%s\n' "$ANDROID_NDK_HOME/ndk-build"
		return 0
	fi
	if [ -n "${NDK_HOME:-}" ] && [ -x "$NDK_HOME/ndk-build" ]; then
		printf '%s\n' "$NDK_HOME/ndk-build"
		return 0
	fi
	command -v ndk-build 2>/dev/null
}

NDK_BUILD="$(find_ndk_build || true)"
if [ -z "$NDK_BUILD" ]; then
	echo "[-] ndk-build not found. Set ANDROID_NDK_HOME/NDK_HOME or add it to PATH." >&2
	exit 1
fi

if [ -z "$JOBS" ]; then
	JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
	JOBS="${JOBS:-4}"
fi

if [ "$CLEAN" -eq 1 ]; then
	rm -rf "$BUILD_ROOT"
fi

mkdir -p "$OBJ_DIR" "$LIBS_DIR" "$(dirname "$OUTPUT")"

echo "[*] NDK: $("$NDK_BUILD" --version 2>/dev/null | head -n1 || printf 'unknown')"
echo "[*] Incremental build dir: $BUILD_ROOT"
echo "[*] Jobs: $JOBS"

(
	cd "$PROJECT_DIR"
	"$NDK_BUILD" \
		NDK_OUT="$OBJ_DIR" \
		NDK_LIBS_OUT="$LIBS_DIR" \
		-j"$JOBS"
)

BUILT="$LIBS_DIR/arm64-v8a/ksu_susfs"
[ -x "$BUILT" ] || {
	echo "[-] expected build output missing: $BUILT" >&2
	exit 1
}

if [ -f "$OUTPUT" ] && cmp -s "$BUILT" "$OUTPUT"; then
	echo "[*] Output unchanged: $OUTPUT"
else
	install -m 0755 "$BUILT" "$OUTPUT"
	echo "[+] Updated: $OUTPUT"
fi

if command -v sha256sum >/dev/null 2>&1; then
	sha256sum "$OUTPUT"
fi
