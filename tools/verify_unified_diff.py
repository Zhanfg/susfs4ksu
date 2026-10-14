#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

HUNK_RE = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$"
)


def verify_patch(path: pathlib.Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    errors: list[str] = []

    for i, line in enumerate(lines):
        match = HUNK_RE.match(line)
        if not match:
            continue

        declared_old = int(match.group(2) or "1")
        declared_new = int(match.group(4) or "1")
        actual_old = 0
        actual_new = 0

        j = i + 1
        while j < len(lines):
            current = lines[j]
            if current.startswith("@@ ") or current.startswith("diff --git "):
                break
            if current.startswith(" "):
                actual_old += 1
                actual_new += 1
            elif current.startswith("-"):
                actual_old += 1
            elif current.startswith("+"):
                actual_new += 1
            elif current.startswith("\\ No newline at end of file"):
                pass
            elif current == "":
                # A truly blank line inside a hunk is malformed: context/add/remove
                # lines must carry a prefix character.
                errors.append(
                    f"{path}:{j + 1}: unprefixed blank line inside hunk starting at {i + 1}"
                )
            else:
                errors.append(
                    f"{path}:{j + 1}: invalid unified-diff line prefix inside hunk "
                    f"starting at {i + 1}: {current[:40]!r}"
                )
            j += 1

        if (declared_old, declared_new) != (actual_old, actual_new):
            errors.append(
                f"{path}:{i + 1}: hunk count mismatch: "
                f"declared old/new={declared_old}/{declared_new}, "
                f"actual={actual_old}/{actual_new}: {line}"
            )

    return errors


def main() -> int:
    if len(sys.argv) > 1:
        paths = [pathlib.Path(arg) for arg in sys.argv[1:]]
    else:
        paths = sorted(pathlib.Path("kernel_patches").rglob("*.patch"))

    errors: list[str] = []
    for path in paths:
        if not path.is_file():
            errors.append(f"{path}: file not found")
            continue
        errors.extend(verify_patch(path))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"verified {len(paths)} patch file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
