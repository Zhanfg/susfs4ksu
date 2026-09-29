#!/system/bin/sh
PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH

MODDIR=${0%/*}
CONFIG_FILE="${SUSFS_CONFIG:-${MODDIR}/config/default.conf}"
RUNTIME_DIR=/dev/.susfs4ksu
SUSFS_BIN=/data/adb/ksu/bin/ksu_susfs

CONTROL_BACKEND=
KSUD_BIN=

log_msg() {
	echo "susfs4ksu: $*" >&2
}

probe_backend() {
	if [ -n "$CONTROL_BACKEND" ]; then
		return 0
	fi

	KSUD_BIN="$(command -v ksud 2>/dev/null)"
	if [ -n "$KSUD_BIN" ] && "$KSUD_BIN" susfs show version >/dev/null 2>&1; then
		CONTROL_BACKEND=ksud-susfs
		return 0
	fi

	if [ -x "$SUSFS_BIN" ] && "$SUSFS_BIN" susfs show version >/dev/null 2>&1; then
		CONTROL_BACKEND=reboot-susfs-v2
		return 0
	fi

	return 1
}

susfs_ctl() {
	probe_backend || {
		log_msg "no compatible SUSFS control backend found"
		return 127
	}

	if [ "$CONTROL_BACKEND" = "ksud-susfs" ]; then
		"$KSUD_BIN" susfs "$@"
	else
		"$SUSFS_BIN" susfs "$@"
	fi
}

is_enabled() {
	[ "${1:-0}" = "1" ] || [ "${1:-}" = "true" ] || [ "${1:-}" = "on" ]
}

apply_post_fs_data() {
	[ -f "$CONFIG_FILE" ] || return 0

	while IFS='=' read -r key value || [ -n "$key$value" ]; do
		case "$key" in
			''|'#'*) continue ;;
			enabled)
				is_enabled "$value" || return 0
				;;
			logging)
				susfs_ctl enable_log "$value" >/dev/null 2>&1 || true
				;;
			avc_log_spoofing)
				susfs_ctl enable_avc_log_spoofing "$value" >/dev/null 2>&1 || true
				;;
			hide_sus_mnts_for_non_su_procs)
				susfs_ctl hide_sus_mnts_for_non_su_procs "$value" >/dev/null 2>&1 || true
				;;
			sus_path)
				[ -n "$value" ] && susfs_ctl add_sus_path "$value" >/dev/null 2>&1 || true
				;;
			open_redirect)
				OLDIFS=$IFS
				IFS='|' read -r target redirected uid_scheme <<EOF
$value
EOF
				IFS=$OLDIFS
				if [ -n "$target" ] && [ -n "$redirected" ] && [ -n "$uid_scheme" ]; then
					susfs_ctl add_open_redirect "$target" "$redirected" "$uid_scheme" >/dev/null 2>&1 || true
				fi
				;;
			uname)
				OLDIFS=$IFS
				IFS='|' read -r release version <<EOF
$value
EOF
				IFS=$OLDIFS
				if [ -n "$release" ] && [ -n "$version" ]; then
					susfs_ctl set_uname "$release" "$version" >/dev/null 2>&1 || true
				fi
				;;
			cmdline_or_bootconfig)
				[ -n "$value" ] && susfs_ctl set_cmdline_or_bootconfig "$value" >/dev/null 2>&1 || true
				;;
		esac
	done < "$CONFIG_FILE"
}

apply_boot_completed() {
	[ -f "$CONFIG_FILE" ] || return 0

	while IFS='=' read -r key value || [ -n "$key$value" ]; do
		case "$key" in
			''|'#'*) continue ;;
			enabled)
				is_enabled "$value" || return 0
				;;
			sus_path_loop)
				[ -n "$value" ] && susfs_ctl add_sus_path_loop "$value" >/dev/null 2>&1 || true
				;;
			sus_map)
				[ -n "$value" ] && susfs_ctl add_sus_map "$value" >/dev/null 2>&1 || true
				;;
		esac
	done < "$CONFIG_FILE"
}

run_stage_once() {
	stage="$1"
	mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
	marker="$RUNTIME_DIR/${stage}.done"

	[ -e "$marker" ] && return 0

	case "$stage" in
		post-fs-data) apply_post_fs_data ;;
		service) : ;;
		boot-completed) apply_boot_completed ;;
		*) log_msg "unknown stage: $stage"; return 2 ;;
	esac

	: > "$marker"
}

show_status() {
	if ! probe_backend; then
		echo "backend=unavailable"
		return 127
	fi

	echo "backend=$CONTROL_BACKEND"
	echo "compat_resukisu=yes"

	if [ "$CONTROL_BACKEND" = "ksud-susfs" ]; then
		printf 'version='
		"$KSUD_BIN" susfs show version 2>/dev/null || true
		printf 'variant='
		"$KSUD_BIN" susfs show variant 2>/dev/null || true
		echo "enabled_features:"
		"$KSUD_BIN" susfs show enabled_features 2>/dev/null || true
	else
		"$SUSFS_BIN" susfs show backend 2>/dev/null || true
		"$SUSFS_BIN" susfs show status 2>/dev/null || true
	fi
}

case "${1:-status}" in
	post-fs-data|service|boot-completed)
		run_stage_once "$1"
		;;
	status)
		show_status
		;;
	backend)
		probe_backend || exit $?
		echo "$CONTROL_BACKEND"
		;;
	*)
		log_msg "usage: controller.sh {post-fs-data|service|boot-completed|status|backend}"
		exit 2
		;;
esac
