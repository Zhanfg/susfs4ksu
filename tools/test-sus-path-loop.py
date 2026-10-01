#!/usr/bin/env python3
"""Execute the actual kernel registration function against host API shims."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "kernel_patches/fs/susfs.c").read_text()
start = source.index("void susfs_add_sus_path_loop(")
end = source.index("\nstatic void susfs_run_sus_path_loop(", start)
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    (directory / "sus-path-loop-under-test.h").write_text(source[start:end])
    executable = directory / "path-test"
    subprocess.run([os.environ.get("CC", "cc"), "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                    "-pthread", f"-I{directory}", f"-I{root / 'kernel_patches/include/uapi'}",
                    str(root / "tests/sus-path-loop.c"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
