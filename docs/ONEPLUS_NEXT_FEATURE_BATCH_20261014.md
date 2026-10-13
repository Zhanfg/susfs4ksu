# SUSFS Next · OnePlus 13 / 6.6 integration batch (2026-10-14)

## Source ancestry and scope

This candidate branches from `vendor/oneplus13-sm8750-a16`, which is **54 commits ahead of `next-6.6`** at the time of staging. That parent already contains the earlier power/performance optimizations, userspace command registry and FUSE-BPF dirty-event work from the modernization branches. They are not new commits in this batch.

This batch cherry-ports **narrow, reviewed files** from:
1. `modernize/portable-core`: module-local fallback executable, atomic helper replacement, validated v2.x backend discovery, hardlink-safe uninstall.
2. `audit/6.6-sus-path-errno-regression`: the known `fs/namei.c` `sus_path` ENOENT/may_lookup source guard.

The Linux 6.6 kernel source, SUSFS kernel hooks, ABI/KMI and OnePlus build configuration remain untouched in this batch. No claim of bypassing integrity checks or general side-channel invisibility is made.

## New behavior

### Root-manager isolation and safe fallback

- The module no longer overwrites `/data/adb/ksu/bin/ksu_susfs` or removes it on uninstall.
- Its standalone ARM64 fallback is installed privately at `$MODPATH/bin/ksu_susfs` by staging a temporary file and renaming it over the old private file.
- This preserves `ksud` and its manager-owned `ksu_susfs` hard links, even when a previous module-private executable was hard-linked to a manager binary.
- Backend probing prefers `ksud susfs` only when both version and variant responses are syntactically valid. Empty/unsupported outputs do not count as supported.
- An unknown SUSFS major version does not silently advertise v2 compatibility.
- Feature discovery errors propagate instead of being reported as successful capability detection.

### Explicit test gate

`python3 tools/test-module-controller.py` uses real shell scripts with mocked backend commands, plus a real hard-link filesystem fixture. It tests:
- native backend preference and fallback to a private helper;
- malformed, missing, or unsupported replies;
- version/variant and feature-query errors;
- stage idempotency;
- safe helper replacement preserving manager hard links.

`python3 tests/check_sus_path_errno.py` statically checks the existing 6.6 patch ordering (`-ENOENT` before `may_lookup()`) against the May 2026 known error-code leak. This **does not** exercise Android VFS syscalls.

## Status and next gates

- [x] Changes staged without mixing in 6.12 kernel code or overwriting current OnePlus 6.6 files
- [ ] Host regression CI confirmed green
- [ ] Full OnePlus 13 `sun_perf` and `sun16k_perf` kernel/Kleaf builds and KMI verified
- [ ] ReSukiSU and KernelSU manager coexistence on Android 17 .103 verified
- [ ] Runtime testing for SELinux, VFS, openat/statx/mount namespace and power complete
- [ ] Existing OnePlus promotion PR #2 merged to `next-6.6`

**Do not merge directly into `gki-android15-6.6` upstream mirror or treat a host-only CI pass as boot validation.** The `modernize/portable-core` experimental kernel UAPI/command dispatcher patch has **not** been imported, as it depends on canonical-core changes absent from the OnePlus branch and needs a separate ABI review.
