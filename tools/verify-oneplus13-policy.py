#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "kernel_patches/fs/susfs.c"
HEADER = ROOT / "kernel_patches/include/linux/susfs.h"
KSU_PATCH = ROOT / "kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
KERNEL_PATCH = ROOT / "kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
MANIFEST = ROOT / "kernel_patches/patchset.json"


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"missing OnePlus policy invariant: {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise SystemExit(f"forbidden OnePlus policy regression: {label}: {needle}")


def patched_view(diff: str) -> str:
    """Return the effective post-patch text represented by a unified diff.

    Removed lines must not participate in policy checks: scanning raw patch
    text would treat a fixed line such as '- if (foo)' as if it still existed.
    """
    out: list[str] = []
    for line in diff.splitlines():
        if line.startswith(("diff --git ", "index ", "--- ", "+++ ", "@@")):
            continue
        if line.startswith("-"):
            continue
        if line.startswith("+"):
            out.append(line[1:])
        else:
            out.append(line)
    return "\n".join(out)


def main() -> int:
    core = CORE.read_text(encoding="utf-8")
    header = HEADER.read_text(encoding="utf-8")
    ksu = KSU_PATCH.read_text(encoding="utf-8")
    ksu_effective = patched_view(ksu)
    kernel_patch = KERNEL_PATCH.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    if manifest["lane"] != "oneplus13-sm8750-a16-6.6":
        raise SystemExit(f"unexpected OnePlus lane: {manifest['lane']}")
    if manifest["kernel"]["baseline_version"] != "6.6.118":
        raise SystemExit(
            f"re-audit policy invariants for new kernel baseline: "
            f"{manifest['kernel']['baseline_version']}"
        )

    require(core, "DEFINE_STATIC_KEY_FALSE(susfs_is_log_enabled);", "logging defaults off")
    require(
        core,
        "static_branch_unlikely(&susfs_is_log_enabled)",
        "disabled logging stays a jump-label fast path",
    )
    require(core, "#define SUSFS_KSTAT_HASH_BITS 10", "kstat table sizing")
    require(core, "#define SUSFS_OPEN_REDIRECT_HASH_BITS 10", "redirect table sizing")

    require(
        core,
        "DEFINE_STATIC_KEY_FALSE(susfs_has_sus_kstat_rules);",
        "empty KSTAT jump-label gate",
    )
    require(
        core,
        "DEFINE_STATIC_KEY_FALSE(susfs_has_open_redirect_rules);",
        "empty open-redirect jump-label gate",
    )
    require(
        core,
        "static_branch_enable(&susfs_has_sus_kstat_rules)",
        "KSTAT gate activates on first valid rule",
    )
    require(
        core,
        "static_branch_enable(&susfs_has_open_redirect_rules)",
        "open-redirect gate activates on first valid rule",
    )

    require(core, "DEFINE_STATIC_KEY_FALSE(susfs_has_sus_path_rules);", "unused SUS_PATH gate")
    require(core, "DEFINE_STATIC_KEY_FALSE(susfs_has_sus_path_loop);", "dynamic path gate")
    require(
        core,
        "strcmp(cursor->target_pathname, new_list->target_pathname)",
        "dynamic path deduplication",
    )

    require(core, "static inline void susfs_mark_fuse_sus_path", "FUSE marker helper")
    require(core, "#ifdef CONFIG_FUSE_BPF", "FUSE-BPF specialization")
    require(core, "fi->backing_inode->i_mapping", "FUSE backing mapping propagation")
    require(
        core,
        "susfs_mark_fuse_sus_map",
        "FUSE-BPF backing SUS_MAP propagation",
    )
    require(
        core,
        "AS_FLAGS_SUS_MAP, &fi->backing_inode->i_mapping->flags",
        "FUSE-BPF backing mmap mark",
    )
    require(
        core,
        ".free_mark = susfs_free_fsnotify_mark",
        "fsnotify mark lifetime finalizer",
    )
    require(
        ksu_effective,
        "!susfs_needs_sus_path_loop_refresh() || work_pending(&susfs_extra_works)",
        "event-aware dynamic-path workqueue suppression",
    )

    forbid(
        core,
        "set_bit(AS_FLAGS_SUS_KSTAT, &fi->backing_inode",
        "do not mark FUSE backing KSTAT without alias-table semantics",
    )
    forbid(
        ksu_effective,
        "if (security_dump_masked_av_fn)",
        "Clang always-true SELinux wrapper check",
    )
    forbid(
        ksu_effective,
        "if (context_struct_compute_av_fn)",
        "Clang always-true SELinux wrapper check",
    )

    for path, text in ((CORE, core), (HEADER, header)):
        if re.search(r"(?<![A-Za-z0-9_])4096(?![A-Za-z0-9_])|0x1000\b", text):
            raise SystemExit(f"hard-coded 4K page-size assumption in {path.relative_to(ROOT)}")

    if re.search(r"^\+.*EXPORT_SYMBOL(?:_GPL)?\(", kernel_patch, re.MULTILINE):
        raise SystemExit("OnePlus kernel patch unexpectedly expands exported KMI surface")

    print("OnePlus 13 SUSFS policy invariants: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
