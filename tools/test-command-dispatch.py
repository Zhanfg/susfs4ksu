#!/usr/bin/env python3
"""Compile the production dispatcher, optionally through a real port adapter."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FEATURES = ["SUS_PATH", "SUS_MOUNT", "SUS_KSTAT", "SPOOF_UNAME", "ENABLE_LOG",
            "SPOOF_CMDLINE_OR_BOOTCONFIG", "OPEN_REDIRECT", "SUS_MAP"]


def function(source: str, name: str) -> str:
    start = source.index(f"int {name}(")
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1] + "\n"
    raise ValueError(f"unterminated function: {name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resukisu-tree", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        core = (ROOT / "kernel_patches/fs/susfs.c").read_text()
        (directory / "dispatch-under-test.h").write_text(function(core, "susfs_handle_command"))
        if args.resukisu_tree:
            port = directory / "port"
            (port / "kernel/supercall").mkdir(parents=True)
            shutil.copy2(args.resukisu_tree / "kernel/supercall/dispatch.c", port / "kernel/supercall/dispatch.c")
            subprocess.run(["git", "init", "-q", str(port)], check=True)
            patch = ROOT / "kernel_patches/ReSukiSU/10_shared_susfs_dispatch.patch"
            subprocess.run(["git", "-C", str(port), "apply", "--check", str(patch)], check=True)
            subprocess.run(["git", "-C", str(port), "apply", str(patch)], check=True)
            adapted = (port / "kernel/supercall/dispatch.c").read_text()
            (directory / "resukisu-under-test.h").write_text(function(adapted, "ksu_handle_susfs_cmd"))
        for enabled in (False, True):
            for adapter in ([0, 1, 2] if args.resukisu_tree else [0]):
                executable = directory / "dispatcher"
                cmd = [os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
                       f"-I{ROOT / 'kernel_patches/include/uapi'}", f"-I{directory}"]
                if enabled:
                    cmd += [f"-DCONFIG_KSU_SUSFS_{feature}" for feature in FEATURES]
                if adapter:
                    cmd += ["-DTEST_RESUKISU"]
                if adapter == 2:
                    cmd += ["-DTEST_RESUKISU_LEGACY"]
                subprocess.run(cmd + [str(ROOT / "tests/command-dispatch.c"), "-o", str(executable)], check=True)
                subprocess.run([str(executable)], check=True)
                port_name = ["core", "ReSukiSU-modern", "ReSukiSU-legacy"][adapter]
                print(f"dispatcher: features={'all' if enabled else 'disabled'} port={port_name}", flush=True)


if __name__ == "__main__":
    main()
