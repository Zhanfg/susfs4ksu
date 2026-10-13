#!/usr/bin/env python3
"""Regression guard for bounded SUS_PATH rules on the OnePlus 6.6 lane.

This is a source contract and exhaustive model of the 256-byte input buffer.
The full kernel object build and live VFS behavior are separate requirements.
"""
from pathlib import Path

text = Path("kernel_patches/fs/susfs.c").read_text(encoding="utf-8")
names = ("susfs_add_sus_path", "susfs_add_sus_path_loop")
fn = {}
for name in names:
    start = text.index(f"void {name}(void __user **user_info) {{")
    end = text.index("\n}\n", start) + 2
    fn[name] = text[start:end]
    copy = fn[name].index("copy_from_user(&info")
    check = fn[name].index("pathname_len = strnlen(info.target_pathname, sizeof(info.target_pathname));")
    reject = fn[name].index("pathname_len ? -ENAMETOOLONG : -EINVAL")
    assert copy < check < reject, name
    assert "pathname_len == sizeof(info.target_pathname)" in fn[name]

static = fn["susfs_add_sus_path"]
dynamic = fn["susfs_add_sus_path_loop"]
assert static.index("pathname_len ? -ENAMETOOLONG") < static.index("kern_path(info.target_pathname")
assert dynamic.index("pathname_len ? -ENAMETOOLONG") < dynamic.index("kzalloc(sizeof(*new_rule)")
assert "memcpy(new_list->target_pathname, info.target_pathname, pathname_len + 1);" in dynamic
assert "strscpy(new_list->target_pathname" not in dynamic
assert dynamic.index("pathname_len ? -ENAMETOOLONG") < dynamic.index("strcmp(cursor->target_pathname")

# All valid terminated inputs (1..255 bytes) survive a 256-byte copy without loss.
for length in range(1, 256):
    payload = b"x" * length + b"\x00" + b"y" * (255 - length)
    assert len(payload) == 256
    length_bounded = payload.find(b"\x00")
    assert length_bounded == length
    dst = bytearray(256)
    dst[:length_bounded + 1] = payload[:length_bounded + 1]
    assert dst[:length_bounded] == payload[:length_bounded]
    assert dst[length_bounded] == 0
assert b"x" * 256 != b"x" * 255 + b"\x00"
for payload in (b"\x00" * 256, b"x" * 256):
    length_bounded = payload.find(b"\x00")
    assert length_bounded in (0, -1)  # Empty or unterminated: rejected.

print("PASS: SUS_PATH/SUS_PATH_LOOP enforce NUL and preserve 255 bytes")
