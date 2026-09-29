#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <susfs_utils.h>
#include <susfs_defs.h>
#include "features.h"

typedef int (*susfs_command_handler_t)(int argc, char *argv[]);
typedef void (*susfs_help_handler_t)(void);

struct susfs_command {
	const char *name;
	susfs_command_handler_t handler;
};

static const struct susfs_command commands[] = {
	{ "add_sus_path", add_sus_path },
	{ "add_sus_path_loop", add_sus_path_loop },
	{ "hide_sus_mnts_for_non_su_procs", hide_sus_mnts_for_non_su_procs },
	{ "add_sus_map", add_sus_map },
	{ "add_open_redirect", add_open_redirect },
	{ "add_sus_kstat_statically", add_sus_kstat_statically },
	{ "add_sus_kstat", add_sus_kstat },
	{ "update_sus_kstat", update_sus_kstat },
	{ "update_sus_kstat_full_clone", update_sus_kstat_full_clone },
	{ "enable_log", enable_log },
	{ "set_cmdline_or_bootconfig", set_cmdline_or_bootconfig },
	{ "enable_avc_log_spoofing", enable_avc_log_spoofing },
	{ "show", show },
	{ "set_uname", set_uname },
};

static const susfs_help_handler_t help_sections[] = {
	sus_path_print_help,
	sus_mount_print_help,
	sus_kstat_print_help,
	sus_map_print_help,
	set_uname_print_help,
	set_cmdline_or_bootconfig_print_help,
	enable_log_print_help,
	enable_avc_log_spoofing_print_help,
	open_redirect_print_help,
	show_print_help,
};

static void print_help(void)
{
	size_t i;

	print_help_banner();
	for (i = 0; i < sizeof(help_sections) / sizeof(help_sections[0]); i++)
		help_sections[i]();
}

static inline void pre_check(int argc)
{
	if (getuid() != 0) {
		log("[-] Must run as root\n");
		exit(-EPERM);
	}

	if (argc < 2) {
		print_help();
		exit(-EINVAL);
	}
}

static int dispatch_command(int argc, char *argv[])
{
	size_t i;

	for (i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
		if (!strcmp(argv[1], commands[i].name))
			return commands[i].handler(argc, argv);
	}

	return -ENOENT;
}

int main(int argc, char *argv[])
{
	int ret;

	pre_check(argc);

	ret = dispatch_command(argc, argv);
	if (ret != -ENOENT)
		return ret;

	print_help();
	return -EINVAL;
}
