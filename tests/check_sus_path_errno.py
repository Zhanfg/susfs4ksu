#!/usr/bin/env python3
"""Static regression guard for the known SUS_PATH errno side channel.

This is NOT a substitute for an unprivileged Android runtime test.
Reported in cctv18/susfs4oki#1; upstream fixed on 2026-05-29.
"""
from pathlib import Path
import re
import sys

PATCH = Path("kernel_patches/50_add_susfs_in_gki-android15-6.6.patch")


def verify_patch() -> None:
    if not PATCH.is_file():
        raise AssertionError(f"missing patch: {PATCH}")
    text = PATCH.read_text(encoding="utf-8")
    sections = re.split(r"(?m)^diff --git ", text)
    namei = [s for s in sections if s.startswith("a/fs/namei.c b/fs/namei.c")]
    if len(namei) != 1:
        raise AssertionError("expected one fs/namei.c diff section")
    hunks = re.split(r"(?m)^@@ ", namei[0])
    targets = [h for h in hunks if "static int link_path_walk(" in h.partition("\n")[0]]
    if len(targets) != 1:
        raise AssertionError("cannot locate unique link_path_walk hunk")
    hunk = targets[0]
    lines = hunk.splitlines()[1:]
    hidden_checks = [i for i, line in enumerate(lines)
                     if re.search(r"^\+\s*if\s*\(.*susfs_is_inode_sus_path\(", line)]
    if len(hidden_checks) != 1:
        raise AssertionError("missing or duplicated SUS_PATH check in link_path_walk")
    check = hidden_checks[0]
    if not any(re.match(r"^\+\s*return\s+-ENOENT;", line)
               for line in lines[check + 1: check + 9]):
        raise AssertionError("hidden descendant must return -ENOENT")
    permission = next((i for i, line in enumerate(lines)
                       if re.search(r"\berr\s*=\s*may_lookup\s*\(", line)), None)
    if permission is None:
        raise AssertionError("cannot confirm standard may_lookup permission handling")
    if not check < permission:
        raise AssertionError("SUS_PATH check follows may_lookup: EACCES/ENOENT leak may return")
    if "CONFIG_KSU_SUSFS_SUS_PATH" not in "\n".join(lines[max(0, check - 4):check + 1]):
        raise AssertionError("SUS_PATH conditional compile guard not found")
    print("PASS: SUS_PATH descendant ENOENT guard precedes may_lookup in 6.6 patch.")
    print("SCOPE: static diff ordering only; run Android non-root stat/faccessat tests before release.")


if __name__ == "__main__":
    try:
        verify_patch()
    except (AssertionError, OSError, UnicodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
