#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <errno.h>
#include <susfs_defs.h>
#include <susfs_utils.h>
#include "show.h"

#define CMD_SUSFS_SHOW_VERSION 0x555e1
#define CMD_SUSFS_SHOW_ENABLED_FEATURES 0x555e2
#define CMD_SUSFS_SHOW_VARIANT 0x555e3

#define SUSFS_ENABLED_FEATURES_SIZE 8192
#define SUSFS_MAX_VERSION_BUFSIZE 16
#define SUSFS_MAX_VARIANT_BUFSIZE 16

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

void show_print_help(void)
{
	log("    show <version|enabled_features|variant|status>\n");
	log("      |--> version: show the current susfs version implemented in kernel\n");
	log("      |--> enabled_features: show the current implemented susfs features in kernel\n");
	log("      |--> variant: show the current variant: GKI or NON-GKI\n");
	log("      |--> status: show version, variant and capabilities in one report\n");
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
	syscall(SYS_reboot, KSU_INSTALL_MAGIC1, SUSFS_MAGIC,
		CMD_SUSFS_SHOW_VERSION, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_VERSION);
	return info->err;
}

static int query_variant(struct st_susfs_variant *info)
{
	memset(info, 0, sizeof(*info));
	info->err = ERR_CMD_NOT_SUPPORTED;
	syscall(SYS_reboot, KSU_INSTALL_MAGIC1, SUSFS_MAGIC,
		CMD_SUSFS_SHOW_VARIANT, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_VARIANT);
	return info->err;
}

static int query_enabled_features(struct st_susfs_enabled_features *info)
{
	memset(info, 0, sizeof(*info));
	info->err = ERR_CMD_NOT_SUPPORTED;
	syscall(SYS_reboot, KSU_INSTALL_MAGIC1, SUSFS_MAGIC,
		CMD_SUSFS_SHOW_ENABLED_FEATURES, info);
	PRT_MSG_IF_CMD_NOT_SUPPORTED(info->err, CMD_SUSFS_SHOW_ENABLED_FEATURES);
	return info->err;
}

static int show_status(void)
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

	if (!strcmp(argv[2], "status"))
		return show_status();

	print_help();
	return -EINVAL;
}
