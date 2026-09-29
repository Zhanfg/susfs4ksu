# Patch and build pipeline

SUSFS Next keeps upstream patch compatibility while replacing the old manual
copy + `patch -p1` sequence with a preflight-first, transactional integration
pipeline.

## Canonical compatibility baseline

The maintained Android 16 / GKI 6.12 lane is described by:

`kernel_patches/patchset.json`

For SUSFS v2.3.0 the reproducible baseline is:

- Android common: `android16-6.12-2025-12_r1`
- Kernel family: `6.12.58`
- KernelSU: pinned by exact commit in the manifest
- Moving compatibility probe: `android16-6.12`

Upstream SUSFS commit `2242ee2409d9c75fadf98d55dc957aef03d489d9`
explicitly states that the 6.12 patches were built with kernel 6.12.58. CI also
verifies that the complete 6.12 patch applies directly to the pinned Android
common release baseline.

The moving branch is deliberately not the reproducible build baseline. It is
used as an early-warning probe for upstream drift.

## Apply SUSFS to a kernel tree

Preflight only:

```bash
tools/susfs-patchctl.sh check \
  --kernel-tree /path/to/kernel/common \
  --ksu-tree /path/to/KernelSU
```

Transactional apply:

```bash
tools/susfs-patchctl.sh apply \
  --kernel-tree /path/to/kernel/common \
  --ksu-tree /path/to/KernelSU
```

The controller:

- reads lane/version/patch defaults from `kernel_patches/patchset.json`
- verifies the kernel major/minor before modification
- validates both kernel and KernelSU patches before mutation
- prefers exact `git apply`
- can recognize an indexed 3-way-compatible patch when old blobs are available
- refuses touched dirty files by default
- refuses to overwrite different canonical SUSFS sources by default
- copies canonical `susfs.c` / headers only after patch preflight succeeds
- rolls the transaction back if a later step fails
- performs post-apply verification
- is safe to run repeatedly on the pinned direct-apply baseline

For manual adaptation work on drifted trees, `tools/hydrate_patch_bases.py`
can materialize only old blobs referenced by patch `index old..new` lines so
`git apply --3way` can work without downloading full kernel history. Routine
CI deliberately does not use this path: the stable lane is direct-only and the
moving tracking lane is a lightweight direct-apply drift probe.

Override switches are intentionally explicit:

- `--allow-dirty`
- `--allow-version-mismatch`
- `--replace-source`

## Userspace and module build

Incremental userspace build:

```bash
./build_ksu_susfs_tool.sh
```

Clean rebuild:

```bash
./build_ksu_susfs_tool.sh --clean
```

Build userspace plus deterministic installable module ZIP:

```bash
./build_all.sh
```

Generated outputs live under `.build/dist`; tracked module sources are not
modified. NDK objects remain under `ksu_susfs/.build` so CI can cache them.

## CI gates

The maintained pipeline has five distinct responsibilities:

1. **Userspace/module CI** — incremental NDK build, deterministic module ZIP,
   and installable artifact upload.
2. **Patch compatibility CI** — unified-diff validation, patchctl transaction
   tests, direct-only pinned baseline application, idempotency, and a
   non-blocking direct-apply probe against current Android common.
3. **Touched-object compile CI** — applies the exact pinned integration and
   compiles every C object touched by the kernel/KernelSU patchset. This catches
   source-level regressions quickly before the slower full Image build.
4. **Control-module CI** — validates the module/controller surface separately.
5. **Full kernel CI** — applies the complete pinned SUSFS + KernelSU patchset,
   enables SUSFS features, compiles an arm64 GKI `Image`, uses `ccache`, and
   publishes the kernel image artifact.

A stable promotion should require the pinned baseline and full kernel build to
pass. Moving-branch drift is diagnostic: it should trigger adaptation work, not
silently redefine the reproducible baseline.

## Patch architecture direction

The large version-specific kernel patch is a compatibility artifact. Canonical
SUSFS implementation sources remain under `kernel_patches/fs` and
`kernel_patches/include`.

Further modernization should split the compatibility patch by subsystem, keep a
machine-readable manifest per maintained GKI lane, regenerate combined patches
from reviewed pieces, and require a complete kernel build before promotion.
