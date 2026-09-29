#ifndef SUSFS_DEFS_H
#define SUSFS_DEFS_H

/*************************
 ** Define Const Values **
 *************************/
#define TAG "ksu_susfs"
#define KSU_INSTALL_MAGIC1 0xDEADBEEF
#define SUSFS_MAGIC 0xFAFAFAFA
#define CMD_SUSFS_QUERY_CAPABILITIES 0x555e5

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

#define SUSFS_MAX_LEN_PATHNAME 256

/******************
 ** Define Macro **
 ******************/
#define ERR_CMD_NOT_SUPPORTED 126
#define log(fmt, msg...) printf(fmt, ##msg);
#define PRT_MSG_IF_CMD_NOT_SUPPORTED(x, cmd) if (x == ERR_CMD_NOT_SUPPORTED) log("[-] CMD: '0x%x', SUSFS operation not supported, please enable it in kernel\n", cmd)

#endif // #ifndef SUSFS_DEFS_H
