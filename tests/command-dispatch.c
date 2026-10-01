#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <linux/susfs_abi.h>

#define __user
static void **expected_arg;
static const char *called;
static unsigned int calls;

#define HANDLER(name) void name(void **arg) { \
	assert(arg == expected_arg); called = #name; calls++; \
}
HANDLER(susfs_add_sus_path)
HANDLER(susfs_add_sus_path_loop)
HANDLER(susfs_set_hide_sus_mnts_for_non_su_procs)
HANDLER(susfs_add_sus_kstat)
HANDLER(susfs_update_sus_kstat)
HANDLER(susfs_set_uname)
HANDLER(susfs_enable_log)
HANDLER(susfs_set_cmdline_or_bootconfig)
HANDLER(susfs_add_open_redirect)
HANDLER(susfs_add_sus_map)
HANDLER(susfs_set_avc_log_spoofing)
HANDLER(susfs_query_capabilities)
HANDLER(susfs_get_enabled_features)
HANDLER(susfs_show_variant)
HANDLER(susfs_show_version)

/* Contains the production function extracted from canonical susfs.c. */
#include "dispatch-under-test.h"

#ifdef TEST_RESUKISU
#ifndef TEST_RESUKISU_LEGACY
#define SUSFS_HAS_COMMAND_DISPATCHER 1
#endif
#include "resukisu-under-test.h"
#define dispatch ksu_handle_susfs_cmd
#else
#define dispatch susfs_handle_command
#endif

#ifdef TEST_RESUKISU_LEGACY
#define UNKNOWN_RESULT 0
#else
#define UNKNOWN_RESULT (-EINVAL)
#endif

int main(void)
{
	void *payload = &payload;
	unsigned int tested = 0;

	expected_arg = &payload;
#define CHECK(cmd, handler) do { \
	calls = 0; called = NULL; \
	assert(dispatch(CMD_SUSFS_##cmd, expected_arg) == 0); \
	assert(calls == 1 && !strcmp(called, #handler)); tested++; \
} while (0)
#define DISABLED(cmd) do { \
	calls = 0; \
	assert(dispatch(CMD_SUSFS_##cmd, expected_arg) == UNKNOWN_RESULT); \
	assert(calls == 0); tested++; \
} while (0)
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	CHECK(ADD_SUS_PATH, susfs_add_sus_path);
	CHECK(ADD_SUS_PATH_LOOP, susfs_add_sus_path_loop);
#else
	DISABLED(ADD_SUS_PATH);
	DISABLED(ADD_SUS_PATH_LOOP);
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	CHECK(HIDE_SUS_MNTS_FOR_NON_SU_PROCS, susfs_set_hide_sus_mnts_for_non_su_procs);
#else
	DISABLED(HIDE_SUS_MNTS_FOR_NON_SU_PROCS);
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
	CHECK(ADD_SUS_KSTAT, susfs_add_sus_kstat);
	CHECK(ADD_SUS_KSTAT_STATICALLY, susfs_add_sus_kstat);
	CHECK(UPDATE_SUS_KSTAT, susfs_update_sus_kstat);
#else
	DISABLED(ADD_SUS_KSTAT);
	DISABLED(ADD_SUS_KSTAT_STATICALLY);
	DISABLED(UPDATE_SUS_KSTAT);
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	CHECK(SET_UNAME, susfs_set_uname);
#else
	DISABLED(SET_UNAME);
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
	CHECK(ENABLE_LOG, susfs_enable_log);
#else
	DISABLED(ENABLE_LOG);
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	CHECK(SET_CMDLINE_OR_BOOTCONFIG, susfs_set_cmdline_or_bootconfig);
#else
	DISABLED(SET_CMDLINE_OR_BOOTCONFIG);
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
	CHECK(ADD_OPEN_REDIRECT, susfs_add_open_redirect);
#else
	DISABLED(ADD_OPEN_REDIRECT);
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	CHECK(ADD_SUS_MAP, susfs_add_sus_map);
#else
	DISABLED(ADD_SUS_MAP);
#endif
	CHECK(ENABLE_AVC_LOG_SPOOFING, susfs_set_avc_log_spoofing);
#ifdef TEST_RESUKISU_LEGACY
	DISABLED(QUERY_CAPABILITIES);
#else
	CHECK(QUERY_CAPABILITIES, susfs_query_capabilities);
#endif
	CHECK(SHOW_ENABLED_FEATURES, susfs_get_enabled_features);
	CHECK(SHOW_VARIANT, susfs_show_variant);
	CHECK(SHOW_VERSION, susfs_show_version);
	calls = 0;
	assert(dispatch(0, expected_arg) == UNKNOWN_RESULT && calls == 0);
	assert(dispatch(CMD_SUSFS_ADD_TRY_UMOUNT, expected_arg) == UNKNOWN_RESULT && calls == 0);
	assert(payload == &payload);
	printf("%u command routes and 2 unknown/deprecated commands passed\n", tested);
	return 0;
}
