#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "kernel_patches/fs/susfs.c").read_text(encoding="utf-8")
KSU = (ROOT / "kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch").read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"missing event-refresh invariant: {label}: {needle}")


def section(text: str, start: str, end: str) -> str:
    a = text.find(start)
    b = text.find(end, a + len(start))
    if a < 0 or b < 0:
        raise SystemExit(f"cannot isolate section: {start!r} -> {end!r}")
    return text[a:b]


def patched_view(diff: str) -> str:
    out: list[str] = []
    for line in diff.splitlines():
        if line.startswith(("diff --git ", "index ", "--- ", "+++ ", "@@")):
            continue
        if line.startswith("-"):
            continue
        out.append(line[1:] if line.startswith("+") else line)
    return "\n".join(out)


def main() -> int:
    require(CORE, "DEFINE_STATIC_KEY_FALSE(susfs_sus_path_spawn_refresh_needed);",
            "separate spawn-refresh jump label")
    require(CORE, "static atomic_t susfs_path_watch_dirty = ATOMIC_INIT(0);",
            "lost-event dirty handshake")
    require(CORE, "static atomic_t susfs_path_watch_epoch = ATOMIC_INIT(0);",
            "event/worker epoch")
    require(CORE, "FS_DELETE_SELF | FS_MOVE_SELF | FS_UNMOUNT",
            "backing inode invalidation mask")
    require(CORE, "fsnotify_destroy_mark(&watch->mark, group);",
            "worker-side watcher teardown")
    require(CORE, ".free_mark = susfs_free_path_watch_mark",
            "watch allocation finalizer")
    require(CORE, "WRITE_ONCE(entry->fallback_required, true);",
            "safe fallback default")
    require(CORE, "if (READ_ONCE(cursor->watch_valid) &&",
            "stable watched-entry scan skip")
    require(CORE, "for (pass = 0; pass < 2; pass++)",
            "bounded race retry")
    require(CORE, "atomic_read(&susfs_path_watch_dirty)",
            "dirty handshake readback")

    handler = section(
        CORE,
        "static int susfs_handle_path_watch_event(",
        "static const struct fsnotify_ops susfs_path_watch_ops",
    )
    for forbidden in (
        "fsnotify_destroy_mark",
        "fsnotify_destroy_group",
        "mutex_lock(",
        "kern_path(",
        "msleep(",
        "schedule_timeout",
    ):
        if forbidden in handler:
            raise SystemExit(
                f"fsnotify callback contains blocking/destructive operation: {forbidden}"
            )

    require(handler, "WRITE_ONCE(entry->watch_valid, false);",
            "callback marks rule dirty")
    require(handler, "atomic_set(&susfs_path_watch_dirty, 1);",
            "callback records dirty handshake")
    require(handler, "schedule_work(&susfs_extra_works);",
            "callback defers refresh to worker")

    effective_ksu = patched_view(KSU)
    require(
        effective_ksu,
        "!susfs_needs_sus_path_loop_refresh() || work_pending(&susfs_extra_works)",
        "KernelSU schedules only on refresh demand",
    )

    # No time-based debounce: correctness must not depend on an exposure window.
    worker = section(
        CORE,
        "static void susfs_run_sus_path_loop(void)",
        "static inline bool is_i_uid_not_allowed",
    )
    if re.search(r"\b(?:msleep|ssleep|schedule_timeout|queue_delayed_work)\b", worker):
        raise SystemExit("dynamic path refresh introduced time-based debounce")

    print("OnePlus event-driven sus_path invariants: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
