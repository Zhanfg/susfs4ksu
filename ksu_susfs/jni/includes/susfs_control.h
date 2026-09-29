#ifndef SUSFS_CONTROL_H
#define SUSFS_CONTROL_H

#include <stdbool.h>
#include <stdint.h>

#define SUSFS_CONTROL_ABI_VERSION 1
#define SUSFS_CONTROL_COMPAT_RESUKISU (1ULL << 0)

long susfs_control_call(uint64_t cmd, void *arg);
const char *susfs_control_transport_name(void);
uint32_t susfs_control_abi_version(void);
uint64_t susfs_control_compat_mask(void);
bool susfs_control_has_compat(uint64_t compat);

#endif /* SUSFS_CONTROL_H */
