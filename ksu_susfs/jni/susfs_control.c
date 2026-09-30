#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/syscall.h>

#include <susfs_defs.h>
#include <susfs_control.h>

/*
 * SUSFS v2.x transport.
 *
 * ReSukiSU's userspace SUSFS implementation currently uses this exact
 * SYS_reboot + KSU_INSTALL_MAGIC1 + SUSFS_MAGIC transport, so this backend
 * remains ABI-compatible without requiring ReSukiSU-specific kernel code.
 */
long susfs_control_call(uint64_t cmd, void *arg)
{
	return syscall(SYS_reboot, KSU_INSTALL_MAGIC1, SUSFS_MAGIC, cmd, arg);
}

const char *susfs_control_transport_name(void)
{
	return "reboot-susfs-v2";
}

uint32_t susfs_control_abi_version(void)
{
	return SUSFS_CONTROL_ABI_VERSION;
}

uint64_t susfs_control_compat_mask(void)
{
	return SUSFS_CONTROL_COMPAT_RESUKISU;
}

bool susfs_control_has_compat(uint64_t compat)
{
	return (susfs_control_compat_mask() & compat) == compat;
}
