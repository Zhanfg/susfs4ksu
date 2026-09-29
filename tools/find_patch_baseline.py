#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass


DIFF_RE = re.compile(r"^diff --git a/(.+?) b/(.+)$")
INDEX_RE = re.compile(r"^index ([0-9a-f]+)\.\.([0-9a-f]+)(?: \d+)?$")


@dataclass(frozen=True)
class ExpectedBlob:
    path: str
    old_prefix: str


def run(repo: pathlib.Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout


def parse_patch(path: pathlib.Path) -> list[ExpectedBlob]:
    current: str | None = None
    result: list[ExpectedBlob] = []

    for line in path.read_text(encoding="utf-8").splitlines():
        match = DIFF_RE.match(line)
        if match:
            current = match.group(1)
            continue

        match = INDEX_RE.match(line)
        if match and current:
            result.append(ExpectedBlob(current, match.group(1)))
            current = None

    if not result:
        raise SystemExit(f"no indexed file entries found in {path}")
    return result


def tree_blobs(repo: pathlib.Path, commit: str, paths: list[str]) -> dict[str, str]:
    out = run(repo, "ls-tree", "-r", "--full-tree", commit, "--", *paths)
    blobs: dict[str, str] = {}
    for line in out.splitlines():
        # <mode> <type> <sha>\t<path>
        head, path = line.split("\t", 1)
        parts = head.split()
        if len(parts) >= 3 and parts[1] == "blob":
            blobs[path] = parts[2]
    return blobs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find a git commit whose file blobs match a unified diff's old index IDs."
    )
    parser.add_argument("--repo", required=True, type=pathlib.Path)
    parser.add_argument("--patch", required=True, type=pathlib.Path)
    parser.add_argument("--max-commits", type=int, default=3000)
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()

    expected = parse_patch(args.patch)
    paths = [item.path for item in expected]

    commits = run(
        args.repo,
        "rev-list",
        "--first-parent",
        f"--max-count={args.max_commits}",
        "HEAD",
    ).splitlines()

    if not commits:
        print("no commits available", file=sys.stderr)
        return 2

    best: list[tuple[int, str, list[str]]] = []

    for idx, commit in enumerate(commits, start=1):
        blobs = tree_blobs(args.repo, commit, paths)
        mismatches: list[str] = []

        for item in expected:
            actual = blobs.get(item.path, "")
            if not actual.startswith(item.old_prefix):
                mismatches.append(item.path)

        score = len(expected) - len(mismatches)
        best.append((score, commit, mismatches))
        best.sort(key=lambda item: (-item[0], commits.index(item[1])))
        del best[args.top :]

        if not mismatches:
            date = run(args.repo, "show", "-s", "--format=%cI", commit).strip()
            print(f"exact_commit={commit}")
            print(f"exact_date={date}")
            print(f"matched_files={len(expected)}")
            return 0

        if idx % 250 == 0:
            print(
                f"scanned={idx} best={best[0][0]}/{len(expected)} {best[0][1]}",
                file=sys.stderr,
            )

    print(f"no exact match in {len(commits)} first-parent commits", file=sys.stderr)
    print("best candidates:", file=sys.stderr)
    for score, commit, mismatches in best:
        date = run(args.repo, "show", "-s", "--format=%cI", commit).strip()
        print(
            f"  {score}/{len(expected)} {commit} {date} "
            f"mismatch={','.join(mismatches[:6])}",
            file=sys.stderr,
        )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
