// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef _UAPI_LINUX_SUSFS_ABI_H
#define _UAPI_LINUX_SUSFS_ABI_H

#include <linux/types.h>

/* Stable v2.x wire ABI. Keep command values and legacy reply layouts unchanged. */
/* shared with userspace ksu_susfs tool */
#define SUSFS_INSTALL_MAGIC1 0xDEADBEEF
#define SUSFS_MAGIC 0xFAFAFAFA
#define CMD_SUSFS_ADD_SUS_PATH 0x55550
#define CMD_SUSFS_SET_ANDROID_DATA_ROOT_PATH 0x55551 /* deprecated */
#define CMD_SUSFS_SET_SDCARD_ROOT_PATH 0x55552 /* deprecated */
#define CMD_SUSFS_ADD_SUS_PATH_LOOP 0x55553
#define CMD_SUSFS_ADD_SUS_MOUNT 0x55560 /* deprecated */
#define CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS 0x55561
#define CMD_SUSFS_UMOUNT_FOR_ZYGOTE_ISO_SERVICE 0x55562 /* deprecated */
#define CMD_SUSFS_ADD_SUS_KSTAT 0x55570
#define CMD_SUSFS_UPDATE_SUS_KSTAT 0x55571
#define CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY 0x55572
#define CMD_SUSFS_ADD_TRY_UMOUNT 0x55580 /* deprecated */
#define CMD_SUSFS_SET_UNAME 0x55590
#define CMD_SUSFS_ENABLE_LOG 0x555a0
#define CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG 0x555b0
#define CMD_SUSFS_ADD_OPEN_REDIRECT 0x555c0
#define CMD_SUSFS_SHOW_VERSION 0x555e1
#define CMD_SUSFS_SHOW_ENABLED_FEATURES 0x555e2
#define CMD_SUSFS_SHOW_VARIANT 0x555e3
#define CMD_SUSFS_QUERY_CAPABILITIES 0x555e5
#define CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE 0x555e4 /* deprecated */
#define CMD_SUSFS_IS_SUS_SU_READY 0x555f0 /* deprecated */
#define CMD_SUSFS_SUS_SU 0x60000 /* deprecated */
#define CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING 0x60010
#define CMD_SUSFS_ADD_SUS_MAP 0x60020

#define SUSFS_MAX_LEN_PATHNAME 256 // 256 should address many paths already unless you are doing some strange experimental stuff, then set your own desired length
#define SUSFS_FAKE_CMDLINE_OR_BOOTCONFIG_SIZE 8192 // 8192 is enough I guess
#define SUSFS_ENABLED_FEATURES_SIZE 8192 // 8192 is enough I guess
#define SUSFS_MAX_VERSION_BUFSIZE 16
#define SUSFS_MAX_VARIANT_BUFSIZE 16
#define SUSFS_CAPS_ABI_VERSION 1

#define SUSFS_CAP_SUS_PATH (1ULL << 0)
#define SUSFS_CAP_SUS_MOUNT (1ULL << 1)
#define SUSFS_CAP_SUS_KSTAT (1ULL << 2)
#define SUSFS_CAP_SPOOF_UNAME (1ULL << 3)
#define SUSFS_CAP_ENABLE_LOG (1ULL << 4)
#define SUSFS_CAP_HIDE_SYMBOLS (1ULL << 5)
#define SUSFS_CAP_SPOOF_CMDLINE_OR_BOOTCONFIG (1ULL << 6)
#define SUSFS_CAP_OPEN_REDIRECT (1ULL << 7)
#define SUSFS_CAP_SUS_MAP (1ULL << 8)
#define SUSFS_CAP_AVC_LOG_SPOOFING (1ULL << 9)

#define SUSFS_ERR_CMD_NOT_SUPPORTED 126

/* get enabled features */
struct st_susfs_enabled_features {
	char                                    enabled_features[SUSFS_ENABLED_FEATURES_SIZE];
	__s32                                   err;
};

/* show variant */
struct st_susfs_variant {
	char                                    susfs_variant[SUSFS_MAX_VARIANT_BUFSIZE];
	__s32                                   err;
};

/* show version */
struct st_susfs_version {
	char                                    susfs_version[SUSFS_MAX_VERSION_BUFSIZE];
	__s32                                   err;
};

/* Versioned, allocation-free capability query ABI. */
struct st_susfs_capabilities {
	__u32                                   abi_version;
	__u32                                   struct_size;
	__u64                                   compiled_features;
	__u64                                   runtime_features;
	char                                    susfs_version[SUSFS_MAX_VERSION_BUFSIZE];
	char                                    susfs_variant[SUSFS_MAX_VARIANT_BUFSIZE];
	__s32                                   err;
	__u32                                   reserved;
};

#endif /* _UAPI_LINUX_SUSFS_ABI_H */
