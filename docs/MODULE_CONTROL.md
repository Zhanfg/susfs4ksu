# Modern control module

The legacy module scripts mixed runtime hooks with large disabled demo blocks. The
new control module is deliberately small and event/stage driven.

## Properties

- no resident daemon
- no polling loop
- no background wakeups
- empty/default configuration performs no SUSFS mutation
- each boot stage is applied at most once using markers in `/dev/.susfs4ksu`
- one backend probe per controller invocation

## Backend selection

1. If `ksud susfs show version` returns a valid version and `show variant`
   returns `GKI` or `NON-GKI`, use the manager-native `ksud susfs` interface.
   This matches current ReSukiSU. Empty, malformed and `Unsupported` replies
   are rejected even when the command exits successfully.
2. Otherwise use the bundled `ksu_susfs susfs ...` control binary.

The command namespace is intentionally compatible with ReSukiSU's SUSFS CLI for
shared operations.

The fallback lives in the module's `bin/ksu_susfs`. ReSukiSU may own a hard link
from `/data/adb/ksu/bin/ksu_susfs` to its `ksud` daemon. The module therefore
installs and removes only its private helper. Status reuses the verified version
and variant, and propagates a failed feature query instead of hiding it.

## Configuration

Edit `config/default.conf`.

Supported v1 keys:

- `enabled`
- `logging`
- `avc_log_spoofing`
- `hide_sus_mnts_for_non_su_procs`
- `sus_path`
- `sus_path_loop`
- `sus_map`
- `open_redirect=target|redirected|uid_scheme`
- `uname=release|version`
- `cmdline_or_bootconfig=/path/to/file`

Repeated path/map/redirect keys are allowed.

## Stage model

- `post-fs-data`: global toggles, static paths, redirect/uname/cmdline
- `service`: currently intentionally empty
- `boot-completed`: dynamic path-loop and map rules

No artificial sleep is used.

## Future v2

The next config ABI should move to a versioned native batch transaction so a
single controller invocation can validate and submit a complete policy without
one syscall per entry. ReSukiSU's add/remove/list configuration semantics will
be mapped onto that API rather than copied into the kernel.
