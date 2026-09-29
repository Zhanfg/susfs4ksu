#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re
from collections import defaultdict

DIFF_RE = re.compile(r"^diff --git a/(.+?) b/(.+)$")
HUNK_RE = re.compile(r"^@@")

CATEGORIES = [
    ("vfs", ("fs/", "include/linux/fs", "include/linux/namei", "include/linux/path")),
    ("mount", ("fs/namespace.c", "fs/proc_namespace.c", "include/linux/mount")),
    ("procfs", ("fs/proc/",)),
    ("mm", ("mm/", "include/linux/mm")),
    ("selinux", ("security/selinux/",)),
    ("sched", ("kernel/", "include/linux/sched")),
    ("uapi", ("include/uapi/",)),
    ("kernelsu", ("kernel/",)),
]

def classify(path: str, is_ksu: bool) -> str:
    if is_ksu:
        return "kernelsu"
    for name, prefixes in CATEGORIES:
        if any(path.startswith(p) for p in prefixes):
            return name
    return "other"

def parse_patch(path: pathlib.Path, is_ksu: bool) -> dict:
    current = None
    files = []
    hunks = 0
    added = 0
    removed = 0
    categories = defaultdict(lambda: {"files": 0, "hunks": 0, "added": 0, "removed": 0})
    current_cat = None

    for line in path.read_text(encoding="utf-8").splitlines():
        m = DIFF_RE.match(line)
        if m:
            current = m.group(2)
            current_cat = classify(current, is_ksu)
            files.append(current)
            categories[current_cat]["files"] += 1
            continue

        if current is None:
            continue

        if HUNK_RE.match(line):
            hunks += 1
            categories[current_cat]["hunks"] += 1
        elif line.startswith("+") and not line.startswith("+++"):
            added += 1
            categories[current_cat]["added"] += 1
        elif line.startswith("-") and not line.startswith("---"):
            removed += 1
            categories[current_cat]["removed"] += 1

    return {
        "patch": str(path),
        "files": files,
        "file_count": len(files),
        "hunks": hunks,
        "added": added,
        "removed": removed,
        "categories": dict(sorted(categories.items())),
    }

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--kernel-patch", required=True, type=pathlib.Path)
    p.add_argument("--ksu-patch", required=True, type=pathlib.Path)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    report = {
        "kernel": parse_patch(args.kernel_patch, False),
        "kernelsu": parse_patch(args.ksu_patch, True),
    }

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0

    for name, data in report.items():
        print(f"{name}: {data['file_count']} files, {data['hunks']} hunks, +{data['added']}/-{data['removed']}")
        for cat, stats in data["categories"].items():
            print(
                f"  {cat:10s} files={stats['files']:2d} hunks={stats['hunks']:3d} "
                f"+{stats['added']:4d}/-{stats['removed']:4d}"
            )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
