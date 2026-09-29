# SUSFS Next control plane

SUSFS Next separates feature logic from the transport used to reach the kernel.

```text
CLI / Manager / automation
          |
          v
    command registry
          |
          v
   SUSFS control API
          |
          +---- reboot-susfs-v2 backend (current)
          |
          +---- future native manager/supercall/ioctl backends
```

## ReSukiSU compatibility

ReSukiSU currently uses the same SUSFS v2.x control transport:

- `SYS_reboot`
- `KSU_INSTALL_MAGIC1 = 0xDEADBEEF`
- `SUSFS_MAGIC = 0xFAFAFAFA`
- the same v2.3 command IDs

The current backend is therefore directly ABI-compatible with ReSukiSU's SUSFS layer.

## Rules

- command IDs have one userspace source of truth
- feature code does not issue the transport syscall directly
- new kernel ABI is capability-probed and additive
- legacy v2.3 commands remain supported
- manager-specific persistence sits above the transport layer

## Next

1. structured controller status for Manager/WebUI
2. declarative config validation + batch application
3. lifecycle operations for add-only kernel state
4. ReSukiSU `ksud susfs` compatibility adapter
5. optional ReSukiSU supercall transport only if it gives measurable value
