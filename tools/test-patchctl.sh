#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHCTL="$ROOT_DIR/tools/susfs-patchctl.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_repo() {
	local dir="$1"
	mkdir -p "$dir"
	git -C "$dir" init -q
	git -C "$dir" config user.name "SUSFS CI"
	git -C "$dir" config user.email "ci@example.invalid"
}

make_kernel_tree() {
	local dir="$1"
	make_repo "$dir"
	cat > "$dir/Makefile" <<'EOF'
VERSION = 6
PATCHLEVEL = 12
EOF
	echo old > "$dir/kernel-target.txt"
	mkdir -p "$dir/fs" "$dir/include/linux"
	git -C "$dir" add .
	git -C "$dir" commit -qm baseline
}

make_ksu_tree() {
	local dir="$1"
	make_repo "$dir"
	echo old > "$dir/ksu-target.txt"
	git -C "$dir" add .
	git -C "$dir" commit -qm baseline
}

make_patch() {
	local dir="$1" file="$2" patch="$3"
	echo new > "$dir/$file"
	git -C "$dir" diff -- "$file" > "$patch"
	git -C "$dir" checkout -q -- "$file"
}

kernel="$tmp/kernel"
ksu="$tmp/ksu"
make_kernel_tree "$kernel"
make_ksu_tree "$ksu"
make_patch "$kernel" kernel-target.txt "$tmp/kernel.patch"
make_patch "$ksu" ksu-target.txt "$tmp/ksu.patch"

common_args=(
	--kernel-tree "$kernel"
	--ksu-tree "$ksu"
	--kernel-patch "$tmp/kernel.patch"
	--ksu-patch "$tmp/ksu.patch"
)

echo "[*] success + idempotency"
bash "$PATCHCTL" check "${common_args[@]}"
bash "$PATCHCTL" apply "${common_args[@]}"
test "$(cat "$kernel/kernel-target.txt")" = new
test "$(cat "$ksu/ksu-target.txt")" = new
cmp "$ROOT_DIR/kernel_patches/fs/susfs.c" "$kernel/fs/susfs.c"
cmp "$ROOT_DIR/kernel_patches/include/linux/susfs.h" "$kernel/include/linux/susfs.h"
cmp "$ROOT_DIR/kernel_patches/include/linux/susfs_def.h" "$kernel/include/linux/susfs_def.h"
cmp "$ROOT_DIR/kernel_patches/include/uapi/linux/susfs_abi.h" "$kernel/include/uapi/linux/susfs_abi.h"
bash "$PATCHCTL" apply "${common_args[@]}"

echo "[*] transactional rollback"
git -C "$kernel" reset --hard -q HEAD
git -C "$ksu" reset --hard -q HEAD
rm -rf "$kernel/fs/susfs.c" "$kernel/include/linux/susfs.h" "$kernel/include/linux/susfs_def.h" "$kernel/include/uapi/linux/susfs_abi.h"
# Create a directory where a regular file must be installed. --replace-source
# allows preflight to continue so the failure happens inside the transaction.
mkdir -p "$kernel/fs/susfs.c"

set +e
bash "$PATCHCTL" apply "${common_args[@]}" --replace-source >/dev/null 2>&1
rc=$?
set -e

test "$rc" -ne 0
test "$(cat "$kernel/kernel-target.txt")" = old
test "$(cat "$ksu/ksu-target.txt")" = old
git -C "$kernel" diff --quiet -- kernel-target.txt
git -C "$ksu" diff --quiet -- ksu-target.txt
test ! -e "$kernel/include/uapi/linux/susfs_abi.h"

echo "[+] patchctl transaction tests passed"
