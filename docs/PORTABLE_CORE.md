# Portable SUSFS core development

The shared core targets algorithm efficiency, smaller kernel/manager adapters,
and reliable feature discovery across KernelSU ports. Device lanes validate
the shared implementation rather than define its public ABI.

## One wire definition

`kernel_patches/include/uapi/linux/susfs_abi.h` owns command IDs, feature bits,
buffer sizes and discovery replies. Kernel and userspace include this same
header. Patchctl installs it alongside the canonical core sources.

The legacy version and variant replies remain 20 bytes, with their error at
offset 16. The legacy feature-string reply remains 8196 bytes. The capability
query remains a 64-byte v1 extension. Existing command numbers are unchanged.
Unknown feature bits can be added; existing bits must not be reassigned.

## ReSukiSU compatibility evidence

The source audit uses ReSukiSU commit
`83850e8e93c5f7cfaec69cf03707f13e799df36a`. Its Rust SUSFS API uses the
same reboot magic values and legacy command IDs, and `repr(C)` discovery
replies with the layouts above. Its kernel dispatcher currently ignores the
new capability command, leaving the caller's unsupported sentinel intact.

The modern client therefore falls back to the three legacy discovery queries
when the extension is unsupported. Permission and malformed-reply errors
remain errors. A successful capability reply must have a supported ABI,
sufficient size, terminated strings and runtime bits within the compiled set.
The kernel constructs runtime bits from its own state, not request contents.

Run `ANDROID_NDK_HOME=/path/to/ndk bash tools/test-control-api.sh` for host
reply tests plus ARM32/ARM64 ABI layout compilation. Tests cover modern and
legacy replies, unsupported commands, permission errors and malformed replies.
These checks do not establish Android device runtime compatibility.

## Shared command bridge

`susfs_handle_command(cmd, arg)` lives in the canonical core. It selects
compiled features and discovery commands for every port. The official
KernelSU adapter now performs its existing magic/root checks and delegates
to this function. No new symbol exports or VFS hooks are introduced.

For an already SUSFS-integrated ReSukiSU kernel, apply
`kernel_patches/ReSukiSU/10_shared_susfs_dispatch.patch` to the pinned
ReSukiSU source specified in `adapter.json`. This small adapter preserves
ReSukiSU's caller authentication. With modern headers it delegates to shared
dispatch, including capability queries; with upstream legacy headers it keeps
the original dispatcher. The official KernelSU patch is a separate adapter
and must not be applied on top of ReSukiSU.

`python3 tools/test-command-dispatch.py --resukisu-tree /path/to/ReSukiSU`
checks direct patch application and exercises the actual patched command
bridge with all optional features enabled and disabled. It works in temporary
files and preserves the supplied port checkout. Complete ReSukiSU kernel
compilation and on-device behavior remain additional integration gates.

## Dynamic rule registration

Dynamic pathname registrations are now idempotent. A 64-bucket writer index
checks exact pathname equality before allocating an entry; hash collisions
never merge different names. Repeated module/stage registration no longer
grows the refresh list. The existing SRCU refresh list and refresh timing stay
in place, so pathname replacement is still resolved on refresh.

On a 64-bit kernel the index adds 512 bytes of buckets and 16 bytes per unique
rule. A refresh resolves each unique registered pathname once, rather than
once per registration. This reduces duplicate work; it does not eliminate
the linear scan of distinct dynamic paths. Unterminated names are rejected,
and the full permitted 255-byte pathname is retained without silent truncation.

`python3 tools/test-sus-path-loop.py` executes the production registration
function with host kernel-API shims. It forces hash collisions, submits 1024
registrations from eight threads, and checks duplicate allocation avoidance,
allocation/copy failures and pathname boundaries. Kernel SRCU and VFS behavior
still require kernel/device tests. Any future removal API must unlink both
containers and wait for SRCU readers before freeing a rule.

## Further work

- Define invalidation and removal lifetimes before adding a path lookup cache.
- Measure lookup cost and table occupancy before adopting adaptive containers.
- Validate each kernel lane and real manager/device behavior before promotion.
