# SUSFS patch decomposition plan

The current Android 16 / 6.12 integration patch remains the validated
compatibility artifact until the full pinned Image build is green.

It should then be decomposed without changing the generated combined diff.

## Proposed ordered layers

1. **00-core-uapi**
   - SUSFS config symbols and shared headers
   - core declarations/flags
   - no VFS behavior by itself

2. **10-vfs-core**
   - path lookup/open/stat/readdir hooks
   - canonical `fs/susfs.c` integration
   - the largest current patch surface

3. **20-mount-engine**
   - namespace/mount ID/group handling
   - mountinfo/mounts filtering
   - fake mount metadata

4. **30-procfs**
   - proc-facing visibility paths not owned by mount engine
   - maps/stat/proc exposure glue

5. **40-mm-map**
   - mmap/maps hiding glue
   - MM-specific hooks only

6. **50-selinux-bridge**
   - SELinux wrappers required by KernelSU/SUSFS integration
   - explicit exported/wrapper interfaces
   - no manager-side policy logic

7. **60-kernelsu-adapter**
   - KernelSU Kconfig/Kbuild
   - KernelSU lifecycle and hook calls
   - SUSFS control bridge

8. **90-compat**
   - version-local compatibility deltas only
   - should remain small and easy to rebase

## Rules

- The ordered component series must regenerate the exact validated combined
  patch before promotion.
- Canonical source files are not duplicated inside component patches.
- A component may depend only on earlier numbered layers.
- Each layer gets an independent `git apply --check` gate.
- KernelSU adapter changes compile through touched-object CI before a full Image
  build.
- Stable GKI lanes remain direct-apply only.
- Tracking branches are diagnostic and never redefine a stable baseline.

## Current impact baseline

The monolithic kernel patch currently touches 25 files / 124 hunks with roughly:

- VFS: +712 lines
- mount: +471 lines
- SELinux: +236 lines
- procfs: +182 lines
- sched/glue: +58 lines
- mm: +13 lines

The KernelSU patch touches 28 files / 97 hunks at approximately +872/-1166.

This is why splitting should follow subsystem boundaries rather than arbitrary
file counts.
