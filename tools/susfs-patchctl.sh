#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="status"
KERNEL_TREE=""
KSU_TREE=""
MANIFEST="$ROOT_DIR/kernel_patches/patchset.json"
KERNEL_PATCH=""
KSU_PATCH=""
MANIFEST_LANE=""
MANIFEST_VERSION=""
MANIFEST_KERNEL_VERSION=""
MANIFEST_KERNEL_PATCH=""
MANIFEST_KSU_PATCH=""
ALLOW_DIRTY=0
ALLOW_VERSION_MISMATCH=0
REPLACE_SOURCE=0

usage() {
	cat <<'EOF'
Usage:
  tools/susfs-patchctl.sh status --kernel-tree PATH --ksu-tree PATH
  tools/susfs-patchctl check  --kernel-tree PATH --ksu-tree PATH
  tools/susfs-patchctl.sh apply  --kernel-tree PATH --ksu-tree PATH [options]

Options:
  --manifest PATH              patchset manifest (default: kernel_patches/patchset.json)
  --kernel-patch PATH          override manifest/auto-selected kernel patch
  --ksu-patch PATH             override manifest KernelSU patch
  --allow-dirty                allow touched target files to have local changes
  --allow-version-mismatch     skip kernel major.minor filename check
  --replace-source             replace existing fs/susfs.c + SUSFS headers if different

The apply command is preflight-first and idempotent:
- both kernel and KernelSU patches are checked before mutation
- already-applied patches are detected with reverse-check
- a later patch failure rolls back a patch applied earlier in the same run
- canonical SUSFS source files are copied only after both patch applications succeed
EOF
}

die() {
	echo "[-] $*" >&2
	exit 1
}

info() {
	echo "[*] $*"
}

ok() {
	echo "[+] $*"
}

if [ "$#" -gt 0 ]; then
	case "$1" in
		status|check|apply)
			MODE="$1"
			shift
			;;
	esac
fi

while [ "$#" -gt 0 ]; do
	case "$1" in
		--manifest)
			MANIFEST="$2"
			shift 2
			;;
		--kernel-tree)
			KERNEL_TREE="$2"
			shift 2
			;;
		--ksu-tree)
			KSU_TREE="$2"
			shift 2
			;;
		--kernel-patch)
			KERNEL_PATCH="$2"
			shift 2
			;;
		--ksu-patch)
			KSU_PATCH="$2"
			shift 2
			;;
		--allow-dirty)
			ALLOW_DIRTY=1
			shift
			;;
		--allow-version-mismatch)
			ALLOW_VERSION_MISMATCH=1
			shift
			;;
		--replace-source)
			REPLACE_SOURCE=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
done

load_manifest() {
	if [ ! -f "$MANIFEST" ]; then
		return 0
	fi

	command -v python3 >/dev/null 2>&1 || die "python3 is required to read patchset manifest: $MANIFEST"

	eval "$(
		python3 - "$MANIFEST" <<'PY'
import json
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

def emit(name, value):
    if value is None:
        value = ""
    print(f"{name}={shlex.quote(str(value))}")

emit("MANIFEST_LANE", data.get("lane"))
emit("MANIFEST_VERSION", data.get("susfs_version"))
emit("MANIFEST_KERNEL_VERSION", data.get("kernel", {}).get("major_minor"))
emit("MANIFEST_KERNEL_PATCH", data.get("patches", {}).get("kernel"))
emit("MANIFEST_KSU_PATCH", data.get("patches", {}).get("kernelsu"))
PY
	)"
}

load_manifest

if [ -z "$KERNEL_PATCH" ] && [ -n "$MANIFEST_KERNEL_PATCH" ]; then
	KERNEL_PATCH="$ROOT_DIR/$MANIFEST_KERNEL_PATCH"
fi
if [ -z "$KSU_PATCH" ] && [ -n "$MANIFEST_KSU_PATCH" ]; then
	KSU_PATCH="$ROOT_DIR/$MANIFEST_KSU_PATCH"
fi
if [ -z "$KSU_PATCH" ]; then
	KSU_PATCH="$ROOT_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
fi

[ -n "$KERNEL_TREE" ] || die "--kernel-tree is required"
[ -n "$KSU_TREE" ] || die "--ksu-tree is required"
[ -d "$KERNEL_TREE/.git" ] || git -C "$KERNEL_TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "kernel tree is not a git worktree: $KERNEL_TREE"
[ -d "$KSU_TREE/.git" ] || git -C "$KSU_TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "KernelSU tree is not a git worktree: $KSU_TREE"
[ -f "$KSU_PATCH" ] || die "KernelSU patch not found: $KSU_PATCH"

select_kernel_patch() {
	if [ -n "$KERNEL_PATCH" ]; then
		[ -f "$KERNEL_PATCH" ] || die "kernel patch not found: $KERNEL_PATCH"
		return
	fi

	mapfile -t patches < <(find "$ROOT_DIR/kernel_patches" -maxdepth 1 -type f -name '50_add_susfs*.patch' -print | LC_ALL=C sort)
	[ "${#patches[@]}" -eq 1 ] || {
		printf '[-] expected exactly one kernel patch on this branch, found %d:\n' "${#patches[@]}" >&2
		printf '    %s\n' "${patches[@]}" >&2
		die "pass --kernel-patch explicitly"
	}
	KERNEL_PATCH="${patches[0]}"
}

select_kernel_patch

if [ -n "$MANIFEST_LANE" ]; then
	info "patchset lane: $MANIFEST_LANE"
fi

kernel_version() {
	local makefile="$KERNEL_TREE/Makefile"
	[ -f "$makefile" ] || return 1
	local major minor
	major="$(awk -F= '/^VERSION[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$makefile")"
	minor="$(awk -F= '/^PATCHLEVEL[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$makefile")"
	[ -n "$major" ] && [ -n "$minor" ] || return 1
	printf '%s.%s\n' "$major" "$minor"
}

expected_version() {
	if [ -n "$MANIFEST_KERNEL_VERSION" ]; then
		printf '%s\n' "$MANIFEST_KERNEL_VERSION"
		return
	fi
	basename "$KERNEL_PATCH" | sed -nE 's/.*-([0-9]+\.[0-9]+)\.patch$/\1/p'
}

verify_manifest_version() {
	[ -n "$MANIFEST_VERSION" ] || return 0
	local actual
	actual="$(sed -nE 's/^#define SUSFS_VERSION "([^"]+)"/\1/p' "$ROOT_DIR/kernel_patches/include/linux/susfs.h" | head -n1)"
	[ -n "$actual" ] || die "cannot read SUSFS_VERSION from canonical header"
	[ "$actual" = "$MANIFEST_VERSION" ] || die "manifest/header SUSFS version mismatch: manifest=$MANIFEST_VERSION header=$actual"
}

verify_version() {
	local actual expected
	actual="$(kernel_version || true)"
	expected="$(expected_version)"

	[ -n "$actual" ] || die "cannot determine kernel VERSION/PATCHLEVEL from $KERNEL_TREE/Makefile"
	info "kernel version: $actual"
	[ -n "$expected" ] && info "patch target version: $expected"

	if [ "$ALLOW_VERSION_MISMATCH" -eq 0 ] && [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
		die "kernel version mismatch: tree=$actual patch=$expected (use --allow-version-mismatch only after manual review)"
	fi
}

patch_state() {
	local tree="$1" patch="$2"
	if git -C "$tree" apply --reverse --check "$patch" >/dev/null 2>&1; then
		echo "applied"
	elif git -C "$tree" apply --check "$patch" >/dev/null 2>&1; then
		echo "ready"
	elif git -C "$tree" apply --3way --check "$patch" >/dev/null 2>&1; then
		echo "ready-3way"
	else
		echo "conflict"
	fi
}

apply_patch_by_state() {
	local tree="$1" patch="$2" state="$3" label="$4"
	case "$state" in
		ready)
			info "applying $label patch (direct)"
			git -C "$tree" apply --whitespace=nowarn "$patch"
			;;
		ready-3way)
			info "applying $label patch (3-way)"
			git -C "$tree" apply --3way --whitespace=nowarn "$patch"
			;;
		applied)
			info "$label patch already applied"
			;;
		*)
			die "$label patch is not applicable: $state"
			;;
	esac
}

patch_paths() {
	awk '/^diff --git a\// { p=$3; sub(/^a\//, "", p); print p }' "$1"
}

assert_touched_files_clean() {
	local tree="$1" patch="$2" label="$3"
	[ "$ALLOW_DIRTY" -eq 1 ] && return 0

	local dirty=0 path
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if ! git -C "$tree" diff --quiet -- "$path" || ! git -C "$tree" diff --cached --quiet -- "$path"; then
			echo "[-] $label target has local changes: $path" >&2
			dirty=1
		fi
	done < <(patch_paths "$patch")

	[ "$dirty" -eq 0 ] || die "refusing to patch dirty target files (use --allow-dirty after review)"
}

source_pairs() {
	cat <<EOF
$ROOT_DIR/kernel_patches/fs/susfs.c|$KERNEL_TREE/fs/susfs.c
$ROOT_DIR/kernel_patches/include/linux/susfs.h|$KERNEL_TREE/include/linux/susfs.h
$ROOT_DIR/kernel_patches/include/linux/susfs_def.h|$KERNEL_TREE/include/linux/susfs_def.h
EOF
}

source_state() {
	local src dst
	while IFS='|' read -r src dst; do
		if [ ! -f "$dst" ]; then
			echo "missing  $dst"
		elif cmp -s "$src" "$dst"; then
			echo "current  $dst"
		else
			echo "different $dst"
		fi
	done < <(source_pairs)
}

assert_source_safe() {
	local src dst
	while IFS='|' read -r src dst; do
		[ -f "$src" ] || die "canonical source missing: $src"
		if [ -e "$dst" ] && ! cmp -s "$src" "$dst" && [ "$REPLACE_SOURCE" -eq 0 ]; then
			die "existing SUSFS source differs: $dst (use --replace-source after review)"
		fi
	done < <(source_pairs)
}

KERNEL_STATE=""
KSU_STATE=""
TXN_DIR=""
TXN_ACTIVE=0
TXN_COMMITTED=0
kernel_applied_now=0
ksu_applied_now=0

backup_sources() {
	TXN_DIR="$(mktemp -d)"
	local src dst index=0
	while IFS='|' read -r src dst; do
		index=$((index + 1))
		if [ -e "$dst" ]; then
			cp -a "$dst" "$TXN_DIR/source-$index"
		else
			: > "$TXN_DIR/source-$index.missing"
		fi
	done < <(source_pairs)
	TXN_ACTIVE=1
}

restore_sources() {
	[ "$TXN_ACTIVE" -eq 1 ] || return 0
	local src dst index=0
	while IFS='|' read -r src dst; do
		index=$((index + 1))
		if [ -f "$TXN_DIR/source-$index.missing" ]; then
			rm -f "$dst"
		elif [ -e "$TXN_DIR/source-$index" ]; then
			mkdir -p "$(dirname "$dst")"
			cp -a "$TXN_DIR/source-$index" "$dst"
		fi
	done < <(source_pairs)
}

rollback_on_exit() {
	local rc=$?
	trap - EXIT INT TERM

	if [ "$TXN_ACTIVE" -eq 1 ] && [ "$TXN_COMMITTED" -eq 0 ]; then
		echo "[!] patch transaction failed; restoring pre-apply state" >&2
		restore_sources
		if [ "$ksu_applied_now" -eq 1 ]; then
			git -C "$KSU_TREE" apply --reverse "$KSU_PATCH" >/dev/null 2>&1 || 				echo "[!] warning: KernelSU rollback failed" >&2
		fi
		if [ "$kernel_applied_now" -eq 1 ]; then
			git -C "$KERNEL_TREE" apply --reverse "$KERNEL_PATCH" >/dev/null 2>&1 || 				echo "[!] warning: kernel rollback failed" >&2
		fi
	fi

	[ -z "$TXN_DIR" ] || rm -rf "$TXN_DIR"
	exit "$rc"
}

verify_post_apply() {
	[ "$(patch_state "$KERNEL_TREE" "$KERNEL_PATCH")" = "applied" ] || 		die "post-apply verification failed: kernel patch is not fully applied"
	[ "$(patch_state "$KSU_TREE" "$KSU_PATCH")" = "applied" ] || 		die "post-apply verification failed: KernelSU patch is not fully applied"

	local src dst
	while IFS='|' read -r src dst; do
		[ -f "$dst" ] && cmp -s "$src" "$dst" || 			die "post-apply verification failed: canonical source mismatch: $dst"
	done < <(source_pairs)
}

preflight() {
	verify_manifest_version
	verify_version

	KERNEL_STATE="$(patch_state "$KERNEL_TREE" "$KERNEL_PATCH")"
	KSU_STATE="$(patch_state "$KSU_TREE" "$KSU_PATCH")"

	info "kernel patch: $KERNEL_STATE ($(basename "$KERNEL_PATCH"))"
	info "KernelSU patch: $KSU_STATE ($(basename "$KSU_PATCH"))"
	source_state | sed 's/^/[*] source: /'

	[ "$KERNEL_STATE" != "conflict" ] || {
		git -C "$KERNEL_TREE" apply --check "$KERNEL_PATCH" || true
		die "kernel patch preflight failed"
	}
	[ "$KSU_STATE" != "conflict" ] || {
		git -C "$KSU_TREE" apply --check "$KSU_PATCH" || true
		die "KernelSU patch preflight failed"
	}

	if [ "$KERNEL_STATE" = "ready" ] || [ "$KERNEL_STATE" = "ready-3way" ]; then
		assert_touched_files_clean "$KERNEL_TREE" "$KERNEL_PATCH" "kernel"
	fi
	if [ "$KSU_STATE" = "ready" ] || [ "$KSU_STATE" = "ready-3way" ]; then
		assert_touched_files_clean "$KSU_TREE" "$KSU_PATCH" "KernelSU"
	fi
	assert_source_safe
}

case "$MODE" in
	status)
		verify_manifest_version
		verify_version
		KERNEL_STATE="$(patch_state "$KERNEL_TREE" "$KERNEL_PATCH")"
		KSU_STATE="$(patch_state "$KSU_TREE" "$KSU_PATCH")"
		echo "kernel_patch=$KERNEL_STATE"
		echo "kernelsu_patch=$KSU_STATE"
		source_state
		;;
	check)
		preflight
		ok "patchset preflight passed; no files modified"
		;;
	apply)
		preflight
		backup_sources
		trap rollback_on_exit EXIT INT TERM

		if [ "$KERNEL_STATE" = "ready" ] || [ "$KERNEL_STATE" = "ready-3way" ]; then
			apply_patch_by_state "$KERNEL_TREE" "$KERNEL_PATCH" "$KERNEL_STATE" "kernel"
			kernel_applied_now=1
		fi

		if [ "$KSU_STATE" = "ready" ] || [ "$KSU_STATE" = "ready-3way" ]; then
			apply_patch_by_state "$KSU_TREE" "$KSU_PATCH" "$KSU_STATE" "KernelSU"
			ksu_applied_now=1
		fi

		while IFS='|' read -r src dst; do
			mkdir -p "$(dirname "$dst")"
			if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
				continue
			fi
			install -m 0644 "$src" "$dst"
		done < <(source_pairs)

		verify_post_apply
		TXN_COMMITTED=1

		ok "SUSFS patchset applied and verified"
		echo "kernel_patch=$(patch_state "$KERNEL_TREE" "$KERNEL_PATCH")"
		echo "kernelsu_patch=$(patch_state "$KSU_TREE" "$KSU_PATCH")"
		;;
esac
