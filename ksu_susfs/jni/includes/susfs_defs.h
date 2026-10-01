#ifndef SUSFS_DEFS_H
#define SUSFS_DEFS_H

/*************************
 ** Define Const Values **
 *************************/
#define TAG "ksu_susfs"
#include <linux/susfs_abi.h>

#define KSU_INSTALL_MAGIC1 SUSFS_INSTALL_MAGIC1

/******************
 ** Define Macro **
 ******************/
#define ERR_CMD_NOT_SUPPORTED SUSFS_ERR_CMD_NOT_SUPPORTED
#define log(fmt, msg...) printf(fmt, ##msg);
#define PRT_MSG_IF_CMD_NOT_SUPPORTED(x, cmd) if (x == ERR_CMD_NOT_SUPPORTED) log("[-] CMD: '0x%x', SUSFS operation not supported, please enable it in kernel\n", cmd)

#endif // #ifndef SUSFS_DEFS_H
