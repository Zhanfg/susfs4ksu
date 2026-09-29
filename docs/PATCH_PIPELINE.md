# Patch and build pipeline

The old integration flow required a long sequence of manual copies and
`patch -p1` commands. SUSFS Next replaces that with a preflight-first patch
controller and incremental/reproducible build scripts.

## Apply SUSFS to a kernel tree

```bash
tools/susfs-patchctl.sh check \
  --kernel-tree /path/to/kernel/common \
  --ksu-tree /path/to/KernelSU

tools/susfs-patchctl.sh apply \
  --kernel-tree /path/to/kernel/common \
  --ksu-tree /path/to/KernelSU
```

`check` performs the complete compatibility test without modifying files.

The controller:

- verifies the kernel major/minor against the branch patch name
- detects already-applied patches
- checks both kernel and KernelSU patches before mutation
- refuses touched dirty files by default
- refuses to overwrite different canonical SUSFS sources by default
- rolls back the kernel patch if the KernelSU patch unexpectedly fails
- is safe to run again after a successful application

Use override switches only after reviewing the local tree:

- `--allow-dirty`
- `--allow-version-mismatch`
- `--replace-source`

## Build

Incremental userspace build:

```bash
./build_ksu_susfs_tool.sh
```

Clean rebuild:

```bash
./build_ksu_susfs_tool.sh --clean
```

Build userspace and reproducible module package:

```bash
./build_all.sh
```

The NDK object directory is preserved under `ksu_susfs/.build`.
CI may cache that directory.

## Patch architecture direction

The large version-specific patch remains a compatibility artifact, not the
source of truth. Shared SUSFS implementation files under `kernel_patches/fs`
and `kernel_patches/include` are canonical.

Next steps:

1. add machine-readable patchset manifests
2. split compatibility glue by subsystem for clearer failures
3. generate/check version-specific patch artifacts from a canonical patch model
4. run application checks against pinned upstream kernel + KernelSU revisions
5. build each maintained GKI lane before promotion to `next`
