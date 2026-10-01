/* Wire replies follow ReSukiSU's repr(C) legacy layouts; no real syscall. */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <susfs_defs.h>
#include <susfs_control.h>
#include "show.h"

static const char *scenario;
static unsigned int queries;

void print_help_banner(void) {}

const char *susfs_control_transport_name(void) { return "test-wire"; }
uint32_t susfs_control_abi_version(void) { return 1; }
bool susfs_control_has_compat(uint64_t compat) { (void)compat; return true; }

long susfs_control_call(uint64_t cmd, void *arg)
{
	queries++;
	if (cmd == CMD_SUSFS_QUERY_CAPABILITIES) {
		struct st_susfs_capabilities *info = arg;

		assert(info->err == ERR_CMD_NOT_SUPPORTED);
		assert(info->abi_version == 1 && info->struct_size == 64);
		if (!strcmp(scenario, "legacy") || !strcmp(scenario, "legacy-string"))
			return 0; /* ReSukiSU ignores unrecognized commands. */
		if (!strcmp(scenario, "legacy-einval")) {
			errno = EINVAL;
			return -1;
		}
		if (!strcmp(scenario, "permission")) {
			errno = EACCES;
			return -1;
		}
		info->err = 0;
		info->compiled_features = SUSFS_CAP_SUS_PATH | SUSFS_CAP_ENABLE_LOG;
		info->runtime_features = SUSFS_CAP_ENABLE_LOG;
		strcpy(info->susfs_version, "v2.3.0");
		strcpy(info->susfs_variant, "GKI");
		if (!strcmp(scenario, "bad-version")) info->abi_version = 2;
		if (!strcmp(scenario, "bad-size")) info->struct_size = 8;
		if (!strcmp(scenario, "bad-bits")) info->runtime_features |= SUSFS_CAP_SUS_MAP;
		if (!strcmp(scenario, "bad-string")) memset(info->susfs_version, 'x', 16);
		return 0;
	}
	if (cmd == CMD_SUSFS_SHOW_VERSION) {
		struct st_susfs_version *info = arg;
		strcpy(info->susfs_version, "v2.3.0");
		info->err = 0;
	} else if (cmd == CMD_SUSFS_SHOW_VARIANT) {
		struct st_susfs_variant *info = arg;
		strcpy(info->susfs_variant, "GKI");
		info->err = 0;
	} else if (cmd == CMD_SUSFS_SHOW_ENABLED_FEATURES) {
		struct st_susfs_enabled_features *info = arg;
		strcpy(info->enabled_features, "CONFIG_KSU_SUSFS_SUS_PATH\n");
		if (!strcmp(scenario, "legacy-string"))
			memset(info->enabled_features, 'x', sizeof(info->enabled_features));
		info->err = 0;
	} else {
		assert(!"unexpected command");
	}
	return 0;
}

int main(int argc, char **argv)
{
	char *args[] = {"ksu_susfs", "show", "status", NULL};
	int expected, result;
	unsigned int expected_queries;

	assert(argc == 2);
	scenario = argv[1];
	expected_queries = 1;
	expected = 0;
	if (!strncmp(scenario, "legacy", 6)) expected_queries = 4;
	if (!strncmp(scenario, "bad-", 4) || !strcmp(scenario, "legacy-string")) expected = -EPROTO;
	if (!strcmp(scenario, "permission")) expected = -EACCES;
	result = show(3, args);
	assert(result == expected);
	assert(queries == expected_queries);
	return 0;
}
