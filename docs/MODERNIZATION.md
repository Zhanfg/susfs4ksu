# SUSFS Next modernization plan

This branch is the integration baseline for the downstream SUSFS modernization work.

## Goals

1. Preserve SUSFS behavior while reducing always-on kernel memory, hot-path work, wakeups, and unnecessary path resolution.
2. Separate shared SUSFS core logic from kernel-version-specific patch glue.
3. Replace fixed oversized or linear data structures with data structures sized for real workloads.
4. Make mount/path hiding event-driven where possible instead of repeatedly rescanning state.
5. Keep upstream mirror branches untouched and maintain clean portability across supported GKI lines.

## Branch model

- `next`: downstream stable line after validation.
- `next-dev`: integration line.
- `modernize/core`: shared core cleanup and internal ABI-safe refactors.
- `modernize/mount-engine`: path/mount hiding architecture.
- `modernize/perf-power`: hot-path, memory and wakeup optimization.
- `port/gki-*`: per-GKI compatibility/validation lanes.
- official `gki-*` and `*-dev` branches: read-only upstream mirrors.

## Baseline observations

The maintained GKI branches currently share identical blobs for:

- `kernel_patches/fs/susfs.c`
- `kernel_patches/include/linux/susfs.h`
- `kernel_patches/include/linux/susfs_def.h`
- `ksu_susfs/jni/main.c`
- `ksu_module_susfs/post-fs-data.sh`
- `ksu_module_susfs/boot-completed.sh`

This allows one canonical core implementation with kernel-version-specific glue isolated in patch files.

### Confirmed hotspots / debt

#### 1. Dynamic hidden-path refresh is process-spawn coupled

`susfs_run_sus_path_loop()` walks every dynamic hidden path and calls `kern_path()` for each entry. It is scheduled from the zygote/setresuid umount path through `susfs_extra_works`.

Cost therefore scales roughly with:

`process spawn frequency × number of dynamic hidden paths × path lookup cost`

Target: move toward dirty/event-driven refresh with bounded fallback validation.

#### 2. Oversized fixed hash tables

Both `SUS_KSTAT_HLIST` and `OPEN_REDIRECT_HLIST` use:

`DEFINE_HASHTABLE(..., 14)`

That allocates 16384 buckets per table. On a 64-bit kernel, the empty bucket arrays alone are approximately 128 KiB each, or ~256 KiB combined before entries are added.

Target: replace with a smaller adaptive structure (preferably rhashtable/xarray where lookup semantics fit), benchmarked against realistic entry counts.

#### 3. Redundant dynamic-path storage

`struct st_susfs_sus_path_list` stores the same 256-byte pathname twice: once inside `info.target_pathname` and once in `target_pathname`. The embedded copy is written but never read by the current kernel implementation.

Target: remove the redundant internal copy without changing userspace ABI.

#### 4. Source-of-truth duplication

The repository contains standalone SUSFS source files and large version-specific patch files that embed overlapping changes.

Target: make shared source canonical and generate/validate version-specific patch artifacts so core changes cannot silently diverge.

#### 5. Boot/module scripts contain demo-oriented and legacy paths

The module scripts mix actual runtime logic with large disabled `cat <<EOF >/dev/null` example blocks and use shell pipelines that can be simplified.

Target: split examples/docs from runtime scripts and minimize boot-time process spawning.

## Optimization constraints

- No regression in path, mount, kstat, map, redirect, uname, cmdline/bootconfig or AVC spoofing behavior.
- No busy polling introduced.
- No new permanent kernel thread.
- Prefer static keys for disabled fast paths.
- Prefer RCU/SRCU read-side lookups where hot-path reads dominate.
- Avoid allocations in VFS hot paths.
- Any new cache must have explicit invalidation semantics.
- Shared-core commits must remain cherry-pickable across all maintained GKI ports.

## Validation gates

Before merging a modernization change into `next`:

1. Build all maintained GKI port branches.
2. Compare enabled feature behavior against upstream v2.3.0.
3. Measure boot-time shell process count and runtime wakeups.
4. Measure kernel resident memory attributable to SUSFS structures.
5. Stress app spawning / zygote transitions.
6. Stress add/update/remove operations for hidden paths, kstat and redirects.
7. Verify no stale entry exposure after file replacement, remount, FUSE recreation or namespace changes.

## First implementation order

1. Internal no-behavior-change cleanup.
2. Remove redundant path storage.
3. Add instrumentation/benchmark hooks behind debug config.
4. Replace fixed oversized hash tables.
5. Redesign dynamic path refresh around invalidation/events.
6. Consolidate mount hiding state and namespace handling.
7. Generate and validate per-GKI patch artifacts from canonical core.
8. Port and test each GKI lane.
