# OnePlus 13 6.6: metadata feature integration evidence

This candidate makes the existing SUS_KSTAT kernel capability reachable through staged module configuration, without changing the underlying VFS hooks, kernel wire ABI, vendor KMI, or disabled-by-default behavior of individual rules.

## Review boundaries

- Integration target: `vendor/oneplus13-sm8750-a16`, not the upstream mirror.
- Kernel SUS_KSTAT symbols: already implemented in the base 6.6 tree.
- Userspace CLI: existing `add_sus_kstat`, `update_sus_kstat`, `update_sus_kstat_full_clone` and static metadata feature commands.
- New controller routes: `kstat_capture` and `kstat_static` at post-fs-data; `kstat_update` and `kstat_update_full_clone` at boot-completed.
- Invalid path, absent metadata, malformed argument counts and backend command errors now fail the stage rather than marking it complete.
- The existing module default configuration enables **no metadata modification**.
- This change must not claim to repair every statx/statfs/FUSE identity inconsistency. Those need kernel-level validation and a separate design.

## Automated evidence

`tools/test-module-controller.py` includes stage ordering, command routing, argument-count rejection, relative path rejection, disabled policy no-op, backend failure/retry, and previous manager-hardlink compatibility tests.

`.github/workflows/metadata-policy-integration.yml` runs the host regression, POSIX shell syntax checks, and a cross-layer source presence gate.

**Unverified**: Android 17 .103 full build, SELinux-enforcing app context behavior, actual statx/statfs semantics, ioctl compatibility, boot/rollback and power benchmarks.

## Release discipline

Do not merge into `next-6.6` or publish a production AK3 until the OnePlus promotion test matrix passes. This is a controller integration branch only; no custom kernel patches are included.
