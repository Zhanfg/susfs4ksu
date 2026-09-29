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
class BaseBlob:
    path: str
    prefix: str


def run(repo: pathlib.Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def parse_patch(path: pathlib.Path) -> list[BaseBlob]:
    current: str | None = None
    result: list[BaseBlob] = []

    for line in path.read_text(encoding="utf-8").splitlines():
        diff = DIFF_RE.match(line)
        if diff:
            current = diff.group(1)
            continue

        index = INDEX_RE.match(line)
        if index and current:
            result.append(BaseBlob(current, index.group(1)))
            current = None

    if not result:
        raise SystemExit(f"no indexed blob entries found in {path}")
    return result


def object_index(repo: pathlib.Path, paths: list[str]) -> dict[str, list[tuple[str, str]]]:
    result: dict[str, list[tuple[str, str]]] = {path: [] for path in paths}
    proc = run(repo, "rev-list", "--objects", "--all", "--", *paths)

    for line in proc.stdout.splitlines():
        if " " not in line:
            continue
        sha, path = line.split(" ", 1)
        if path in result:
            result[path].append((sha, path))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Hydrate old blob objects referenced by a unified diff in a partial clone."
    )
    parser.add_argument("--repo", required=True, type=pathlib.Path)
    parser.add_argument("--patch", required=True, type=pathlib.Path)
    args = parser.parse_args()

    expected = parse_patch(args.patch)
    by_path = object_index(args.repo, sorted({item.path for item in expected}))

    missing: list[str] = []
    hydrated = 0

    for item in expected:
        matches = [
            sha for sha, _ in by_path.get(item.path, [])
            if sha.startswith(item.prefix)
        ]
        if not matches:
            missing.append(f"{item.path}:{item.prefix}")
            continue

        sha = matches[0]
        # In a promisor/partial clone this materializes only the requested blob.
        proc = run(args.repo, "cat-file", "-e", f"{sha}^{{blob}}", check=False)
        if proc.returncode != 0:
            missing.append(f"{item.path}:{item.prefix}")
            continue

        hydrated += 1
        print(f"hydrated {item.path} {sha}")

    if missing:
        print(
            f"missing {len(missing)}/{len(expected)} patch base blob(s):",
            file=sys.stderr,
        )
        for item in missing:
            print(f"  {item}", file=sys.stderr)
        return 2

    print(f"hydrated {hydrated}/{len(expected)} patch base blobs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
