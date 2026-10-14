# OnePlus 13 / SM8750 Android 16 lane

This lane targets the official OnePlus 13 Android 16 OSS stack.

## Pinned OSS inputs

- Common kernel: `OnePlusOSS/android_kernel_common_oneplus_sm8750`
  - branch: `oneplus/sm8750_b_16.0.0_oneplus_13`
  - commit: `e1b346b6b4f4096eb342ae3684838a942fd6f6c4`
  - kernel: `6.6.118`
  - Qualcomm base: `android15-6.6-2026-01_r22`
- Qualcomm/OPlus kernel: `OnePlusOSS/android_kernel_oneplus_sm8750`
  - commit: `6028f47faddaa27700f8dd3a1d83906ea8f27170`
- Modules + devicetree:
  `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750`
  - commit: `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3`

The published sync commit covers OnePlus 13 variants CPH2649, CPH2653 and
PJZ110 on the 16.0.9.401 source drop.

## Why this is not the generic Android 16 / 6.12 lane

OnePlus 13 stays on a 6.6 GKI/common base while running Android 16. The correct
SUSFS compatibility starting point is therefore the maintained
`gki-android15-6.6` patch family, followed by device/vendor validation.

## OnePlus-specific priorities

### 1. FUSE-BPF / backing inode awareness

The OnePlus common arm64 GKI config enables `CONFIG_FUSE_BPF=y`, and its
`struct fuse_inode` contains a separate `backing_inode`.

SUSFS dynamic path hiding currently marks the visible FUSE inode/mapping. The
OnePlus port should also validate and, where safe, mark the backing inode
mapping so passthrough/backing operations do not bypass the intended state.

This must remain conditional on `CONFIG_FUSE_BPF` and a non-NULL backing
inode, so generic 6.6 behavior is unchanged.


### 1.1. Do not bit-propagate SUS_KSTAT blindly

`SUS_PATH` can safely propagate its address-space flag to a FUSE-BPF
`backing_inode` because the decision is local to the inode/mapping flag.

`SUS_KSTAT` is different: its spoof table is keyed by inode/device identity and
tracks whether the entry is FUSE. Marking only the backing inode mapping would
make the backing path enter the SUS_KSTAT path with a different `(ino, dev,
is_fuse)` identity and then fail to find the original FUSE hash entry.

Therefore this lane intentionally does **not** copy `AS_FLAGS_SUS_KSTAT` to the
backing inode. A future implementation must create and maintain an explicit
backing-identity alias/secondary entry, including update/removal lifetime rules,
rather than adding a standalone bit.

### 2. Reduce app-spawn work

Keep the generic SUSFS Next static-key optimization: when no dynamic
`sus_path_loop` rules exist, do not queue extra SUSFS work from zygote
setresuid handling.

For configured dynamic rules, prefer event/invalidation-driven refresh over a
full `kern_path()` scan per spawn.

### 3. Preserve KMI/vendor module compatibility

OnePlus publishes common kernel separately from Qualcomm/OPlus kernel modules
and device tree. SUSFS changes should avoid changing exported function
signatures or vendor-hook contracts unless unavoidable.

Any future hook-based OnePlus optimization should live in the vendor adapter
rather than expanding the generic VFS patch.

### 4. Vendor-hook opportunities

The OnePlus common tree contains Android vendor-hook infrastructure, including
FUSE/fsnotify/workqueue related hooks. These should be audited as potential
low-patch-surface integration points. They are not automatically preferable:
SUSFS semantics that require changing VFS return values still belong in the
core patch.

## Promotion gates

1. exact OnePlus common 6.6.118 direct patch preflight;
2. KernelSU patch direct preflight;
3. FUSE-BPF/backing-inode assumptions checked against official source;
4. touched-object compilation on the OnePlus common tree;
5. KMI/vendor-module compatibility check;
6. complete OnePlus kernel integration build before device testing.
