#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <errno.h>
#include <susfs_defs.h>
#include <susfs_control.h>
#include <susfs_utils.h>
#include "show.h"



struct st_susfs_enabled_features {
	char enabled_features[SUSFS_ENABLED_FEATURES_SIZE];
	int err;
};

struct st_susfs_variant {
	char susfs_variant[SUSFS_MAX_VARIANT_BUFSIZE];
	int err;
};

struct st_susfs_version {
	char susfs_version[SUSFS_MAX_VERSION_BUFSIZE];
	int err;
};

struct st_susfs_capabilities {
	uint32_t abi_version;
	uint32_t struct_size;
	uint64_t compiled_features;
	uint64_t runtime_features;
	char susfs_version[SUSFS_MAX_VERSION_BUFSIZE];
	char susfs_variant[SUSFS_MAX_VARIANT_BUFSIZE];
	int32_t err;
	uint32_t reserved;
};

struct capability_name {
	uint64_t bit;
	const char *name;
};

static const struct capability_name capability_names[] = {
	{ SUSFS_CAP_SUS_PATH, "sus_path" },
	{ SUSFS_CAP_SUS_MOUNT, "sus_mount" },
	{ SUSFS_CAP_SUS_KSTAT, "sus_kstat" },
	{ SUSFS_CAP_SPOOF_UNAME, "spoof_uname" },
	{ SUSFS_CAP_ENABLE_LOG, "enable_log" },
	{ SUSFS_CAP_HIDE_SYMBOLS, "hide_symbols" },
	{ SUSFS_CAP_SPOOF_CMDLINE_OR_BOOTCONFIG, "spoof_cmdline_or_bootconfig" },
	{ SUSFS_CAP_OPEN_REDIRECT, "open_redirect" },
	{ SUSFS_CAP_SUS_MAP, "sus_map" },
	{ SUSFS_CAP_AVC_LOG_SPOOFING, "avc_log_spoofing" },
};

void show_print_help(void)
{
	log("    show <version|enabled_features|variant|status|capabilities|backend>\n");
	log("      |--> version: show the current susfs version implemented in kernel\n");
	log("      |--> enabled_features: show the current implemented susfs features in kernel\n");
	log("      |--> variant: show the current variant: GKI or NON-GKI\n");
	log("      |--> status: show version, variant and capabilities in one report\n");
	log("      |--> capabilities: alias of status; prefers the versioned capability ABI\n");
	log("      |--> backend: show control-plane transport and compatibility profiles\n");
	log("\n");
}

static void print_help(void)
{
	print_help_banner();
	show_print_help();
}

static int query_version(struct st_susfs_version *info)
{
	memset(info, 0, sizeof(*info));
	info->err = ERR_CMD_NOT_SUPPORTED;
	susfs_control_call(CMD_SUSFS_SHOW_VERSION, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_VERSION);
	return info->err;
}

static int query_variant(struct st_susfs_variant *info)
{
	memset(info, 0, sizeof(*info));
	info->err = ERR_CMD_NOT_SUPPORTED;
	susfs_control_call(CMD_SUSFS_SHOW_VARIANT, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_VARIANT);
	return info->err;
}

static int query_enabled_features(struct st_susfs_enabled_features *info)
{
	memset(info, 0, sizeof(*info));
	info->err = ERR_CMD_NOT_SUPPORTED;
	susfs_control_call(CMD_SUSFS_SHOW_ENABLED_FEATURES, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_ENABLED_FEATURES);
	return info->err;
}

static int query_capabilities(struct st_susfs_capabilities *info)
{
	memset(info, 0, sizeof(*info));
	info->abi_version = SUSFS_CAPS_ABI_VERSION;
	info->struct_size = sizeof(*info);
	info->err = ERR_CMD_NOT_SUPPORTED;
	susfs_control_call(CMD_SUSFS_QUERY_CAPABILITIES, info);
	return info->err;
}

static void print_capability_set(const char *label, uint64_t features)
{
	size_t i;

	log("%s:\n", label);
	for (i = 0; i < sizeof(capability_names) / sizeof(capability_names[0]); i++) {
		if (features & capability_names[i].bit)
			log("  %s\n", capability_names[i].name);
	}
}

static int show_backend(void)
{
	log("control_abi=%u\n", susfs_control_abi_version());
	log("transport=%s\n", susfs_control_transport_name());
	log("resukisu_compatible=%s\n",
		susfs_control_has_compat(SUSFS_CONTROL_COMPAT_RESUKISU) ? "yes" : "no");
	return 0;
}

static int show_capabilities(void)
{
	struct st_susfs_capabilities info;
	int err = query_capabilities(&info);

	if (err)
		return err;

	log("abi_version=%u\n", info.abi_version);
	log("struct_size=%u\n", info.struct_size);
	log("version=%s\n", info.susfs_version);
	log("variant=%s\n", info.susfs_variant);
	log("compiled_features=0x%016llx\n",
		(unsigned long long)info.compiled_features);
	log("runtime_features=0x%016llx\n",
		(unsigned long long)info.runtime_features);
	print_capability_set("compiled", info.compiled_features);
	print_capability_set("runtime_enabled", info.runtime_features);
	return 0;
}

static int show_status_legacy(void)
{
	struct st_susfs_version version;
	struct st_susfs_variant variant;
	struct st_susfs_enabled_features *features;
	int err;

	err = query_version(&version);
	if (err)
		return err;

	err = query_variant(&variant);
	if (err)
		return err;

	features = malloc(sizeof(*features));
	if (!features) {
		perror("malloc");
		return -ENOMEM;
	}

	err = query_enabled_features(features);
	if (err) {
		free(features);
		return err;
	}

	log("version=%s\n", version.susfs_version);
	log("variant=%s\n", variant.susfs_variant);
	log("enabled_features:\n%s", features->enabled_features);
	if (features->enabled_features[0] != '\0') {
		size_t len = strlen(features->enabled_features);
		if (features->enabled_features[len - 1] != '\n')
			log("\n");
	}

	free(features);
	return 0;
}

int show(int argc, char *argv[])
{
	if (argc != 3) {
		print_help();
		return -EINVAL;
	}

	if (!strcmp(argv[2], "version")) {
		struct st_susfs_version info;

		if (query_version(&info))
			return info.err;
		log("%s\n", info.susfs_version);
		return 0;
	}

	if (!strcmp(argv[2], "enabled_features")) {
		struct st_susfs_enabled_features *info;
		int err;

		info = malloc(sizeof(*info));
		if (!info) {
			perror("malloc");
			return -ENOMEM;
		}

		err = query_enabled_features(info);
		if (!err)
			log("%s", info->enabled_features);
		free(info);
		return err;
	}

	if (!strcmp(argv[2], "variant")) {
		struct st_susfs_variant info;

		if (query_variant(&info))
			return info.err;
		log("%s\n", info.susfs_variant);
		return 0;
	}

	if (!strcmp(argv[2], "backend"))
		return show_backend();

	if (!strcmp(argv[2], "status") || !strcmp(argv[2], "capabilities")) {
		int err = show_capabilities();

		if (err == ERR_CMD_NOT_SUPPORTED)
			return show_status_legacy();
		return err;
	}

	print_help();
	return -EINVAL;
}
