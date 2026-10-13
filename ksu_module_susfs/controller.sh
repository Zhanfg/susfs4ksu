#!/system/bin/sh
PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH

MODDIR=${0%/*}
CONFIG_FILE="${SUSFS_CONFIG:-${MODDIR}/config/default.conf}"
RUNTIME_DIR="${SUSFS_RUNTIME_DIR:-/dev/.susfs4ksu}"
SUSFS_BIN="${SUSFS_BIN:-${MODDIR}/bin/ksu_susfs}"

CONTROL_BACKEND=
CONTROL_VERSION=
CONTROL_VARIANT=
KSUD_BIN="${SUSFS_KSUD_BIN:-}"

log_msg() {
	echo "susfs4ksu: $*" >&2
}

probe_candidate() {
	CANDIDATE_VERSION="$("$1" susfs show version 2>/dev/null)" || return 1
	case "$CANDIDATE_VERSION" in v*) ;; *) return 1 ;; esac
	release=${CANDIDATE_VERSION#v}
	case "$release" in *.*.*) ;; *) return 1 ;; esac
	major=${release%%.*}
	release=${release#*.}
	minor=${release%%.*}
	release=${release#*.}
	patch=${release%%[-+]*}
	suffix=${release#"$patch"}
	for part in "$major" "$minor" "$patch"; do
		case "$part" in ''|*[!0-9]*) return 1 ;; esac
	done
	case "$suffix" in
		'') ;;
		[-+][0-9A-Za-z]*)
			case "$suffix" in *[!0-9A-Za-z._+-]*) return 1 ;; esac
			;;
		*) return 1 ;;
	esac
	CANDIDATE_VARIANT="$("$1" susfs show variant 2>/dev/null)" || return 1
	case "$CANDIDATE_VARIANT" in GKI|NON-GKI) ;; *) return 1 ;; esac
}

probe_backend() {
	if [ -n "$CONTROL_BACKEND" ]; then
		return 0
	fi

	if [ -z "$KSUD_BIN" ]; then
		KSUD_BIN="$(command -v ksud 2>/dev/null)"
	fi
	if [ -n "$KSUD_BIN" ] && probe_candidate "$KSUD_BIN"; then
		CONTROL_BACKEND=ksud-susfs
		CONTROL_VERSION=$CANDIDATE_VERSION
		CONTROL_VARIANT=$CANDIDATE_VARIANT
		return 0
	fi

	if [ -x "$SUSFS_BIN" ] && probe_candidate "$SUSFS_BIN"; then
		CONTROL_BACKEND=reboot-susfs-v2
		CONTROL_VERSION=$CANDIDATE_VERSION
		CONTROL_VARIANT=$CANDIDATE_VARIANT
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

	probe_backend || {
		log_msg "cannot apply $stage: no compatible backend"
		return 127
	}

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
	case "$CONTROL_VERSION" in
		v2.*) echo "compat_resukisu=yes" ;;
		*) echo "compat_resukisu=unknown" ;;
	esac
	echo "version=$CONTROL_VERSION"
	echo "variant=$CONTROL_VARIANT"
	echo "enabled_features:"
	susfs_ctl show enabled_features
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
