#!/bin/sh
# amicus-native-recovery-v1

set -eu

# Keep these sentinels split so release publishing only rewrites the configured
# values below; local or unpublished copies still need unreplaced values to compare.
amicus_unconfigured_base_url="__AMICUS_DOWNLOAD_BASE""_URL__"
amicus_unconfigured_default_release_channel="__AMICUS_DEFAULT_RELEASE_""CHANNEL__"
amicus_base_url="${AMICUS_DOWNLOAD_BASE_URL:-__AMICUS_DOWNLOAD_BASE_URL__}"
amicus_base_url="${amicus_base_url%/}"
amicus_default_release_channel="__AMICUS_DEFAULT_RELEASE_CHANNEL__"
if [ "$amicus_default_release_channel" = "$amicus_unconfigured_default_release_channel" ]; then
	amicus_default_release_channel=stable
fi
amicus_release_channel="${AMICUS_RELEASE_CHANNEL:-$amicus_default_release_channel}"
amicus_package="${AMICUS_PACKAGE:-amicus}"
amicus_cmd="${AMICUS_CMD:-amicus}"
amicus_esc=$(printf '\033')
amicus_original_path="${PATH:-}"
amicus_reset="${amicus_esc}[0m"
amicus_bold="${amicus_esc}[1m"
amicus_italic="${amicus_esc}[3m"
amicus_hide_cursor="${amicus_esc}[?25l"
amicus_show_cursor="${amicus_esc}[?25h"
amicus_home_cursor="${amicus_esc}[H"
amicus_clear_screen="${amicus_esc}[2J${amicus_esc}[H"
amicus_clear_line="${amicus_esc}[K"
amicus_sync_start="${amicus_esc}[?2026h"
amicus_sync_end="${amicus_esc}[?2026l"
amicus_color_text="${amicus_esc}[38;2;244;244;245m"
amicus_color_muted="${amicus_esc}[38;2;161;161;170m"
amicus_color_dim="${amicus_esc}[38;2;113;113;122m"
amicus_color_primary="${amicus_esc}[38;2;127;91;213m"
amicus_color_scan="${amicus_esc}[38;2;14;165;233m"
amicus_color_warning="${amicus_esc}[38;2;245;158;11m"
readonly amicus_unconfigured_base_url amicus_unconfigured_default_release_channel amicus_base_url amicus_default_release_channel amicus_release_channel amicus_package amicus_cmd amicus_esc amicus_original_path
readonly amicus_reset amicus_bold amicus_italic amicus_hide_cursor amicus_show_cursor amicus_home_cursor amicus_clear_screen amicus_clear_line
readonly amicus_sync_start amicus_sync_end
readonly amicus_color_text amicus_color_muted amicus_color_dim amicus_color_primary amicus_color_scan amicus_color_warning

amicus_screen_enabled=0
amicus_screen_frame=0
amicus_screen_cols=80
amicus_screen_rows=24
amicus_screen_drawn=0
amicus_screen_last_cols=0
amicus_screen_last_rows=0
amicus_screen_layout_ready=0
amicus_screen_layout_show_logo=0
amicus_screen_layout_lab_width=0
amicus_screen_render_lab_width=0
amicus_screen_compact=0
amicus_download_dir=
amicus_bootstrap_kernel_on_install=0
amicus_screen_title=
amicus_screen_status=
amicus_screen_detail=
amicus_screen_question=
amicus_animation_frame=0
amicus_native_stage=
amicus_native_lock=
amicus_allow_insecure_http=0
# Tests point platform detection at a fake /proc and /lib without needing a container.
amicus_native_sysroot="${AMICUS_NATIVE_SYSROOT_FOR_TESTS:-}"

main() {
	if [ "${1:-}" = --rollback ]; then
		amicus_native_rollback
		return
	fi
	if [ "${1:-}" = --native-platform ]; then
		amicus_native_platform
		return
	fi
	case "${AMICUS_INSTALL_METHOD:-auto}" in
		auto|binary|node) ;;
		*) printf 'error: AMICUS_INSTALL_METHOD must be auto, binary or node.\n' >&2; exit 1 ;;
	esac
	if [ "${AMICUS_INSTALL_METHOD:-auto}" != node ]; then
		if native_platform=$(amicus_native_platform); then
			amicus_install_native "$native_platform" "$@"
			return
		fi
		if [ "${AMICUS_INSTALL_METHOD:-auto}" = binary ]; then
			printf 'error: no compatible compiled archive is available for this platform.\n' >&2
			exit 1
		fi
		printf 'Using the Node installation for this platform.\n' >&2
	fi
	amicus_install_node "$@"
}

amicus_install_node() {
	if [ "$amicus_base_url" = "$amicus_unconfigured_base_url" ]; then
		printf 'error: installer download URL is not configured.\n' >&2
		printf 'Set AMICUS_DOWNLOAD_BASE_URL or use the installer published by the release workflow.\n' >&2
		exit 1
	fi
	amicus_validate_download_base_url

	amicus_install_traps
	amicus_init_screen
	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "Installing Amicus" "" "" ""
	else
		printf '\n\033[1m  Installing Amicus\033[0m\n\033[2m  npm global install\033[0m\n\n'
	fi

	start_preflight_checks

	if finish_preflight_checks; then
		check_status=0
	else
		check_status=$?
	fi

	if [ "$check_status" -ne 0 ]; then
		if ! install_node_npm_interactive; then
			exit "$check_status"
		fi

		start_preflight_checks
		if finish_preflight_checks; then
			check_status=0
		else
			check_status=$?
		fi

		if [ "$check_status" -ne 0 ]; then
			exit "$check_status"
		fi
	fi

	version="$(resolve_amicus_version "$@")"
	tarball_name="$amicus_package-$version.tgz"
	tarball_url="$amicus_base_url/releases/v$version/$tarball_name"

	confirm_install "$version" "$tarball_url"
	confirm_kernel_runtime_setup

	download_dir=$(create_temp_dir)
	amicus_download_dir="$download_dir"
	tarball_path="$download_dir/$tarball_name"

	download_amicus_package "$version" "$tarball_url" "$tarball_path"
	install_amicus_package "$tarball_path"
	rm -rf "$download_dir"
	amicus_download_dir=

	if [ "${AMICUS_NODE_INSTALLED_STANDALONE:-0}" = 1 ]; then
		amicus_screen "Amicus installed" "" "Checking your shell PATH." ""
		configure_standalone_node_path
	elif command -v "$amicus_cmd" >/dev/null 2>&1; then
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_screen "Amicus installed" "" "Run it with: $amicus_cmd" ""
		else
			printf '\nAmicus was installed successfully.\n'
			printf '\nRun it with: %s\n' "$amicus_cmd"
		fi
	else
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_screen "Amicus installed" "" "PATH update needed for $amicus_cmd." ""
			amicus_restore_terminal
		else
			printf '\nAmicus was installed successfully.\n'
		fi
		cat <<EOF
The $amicus_cmd command was installed, but it is not on your PATH yet.
Check npm's global bin directory with:

  npm bin -g

Then add that directory to your shell PATH.
EOF
	fi
}

create_temp_dir() {
	if command -v mktemp >/dev/null 2>&1; then
		if tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/amicus-install.XXXXXX" 2>/dev/null); then
			printf '%s' "$tmp_dir"
			return
		fi
	fi

	printf 'error: mktemp is required to create a secure temporary directory.\n' >&2
	exit 1
}

amicus_is_loopback_test_base_url() {
	case "$1" in
		http://127.0.0.1:*) ;;
		*) return 1 ;;
	esac
	test_port=${1##*:}
	case "$test_port" in ''|*[!0-9]*) return 1 ;; esac
}

amicus_validate_download_base_url() {
	case "$amicus_base_url" in
		https://*)
			amicus_allow_insecure_http=0
			;;
		http://*)
			if [ "${AMICUS_ALLOW_INSECURE_HTTP_FOR_TESTS:-0}" = 1 ] &&
				amicus_is_loopback_test_base_url "$amicus_base_url"; then
				amicus_allow_insecure_http=1
				return
			fi
			printf 'error: Amicus downloads require an HTTPS base URL.\n' >&2
			printf 'Local loopback test feeds require AMICUS_ALLOW_INSECURE_HTTP_FOR_TESTS=1.\n' >&2
			exit 1
			;;
		*)
			printf 'error: Amicus download base URL must use HTTPS.\n' >&2
			exit 1
			;;
	esac
}

amicus_curl_download() {
	if [ "$amicus_allow_insecure_http" = 1 ]; then
		curl --proto '=http,https' --proto-redir '=https' "$@"
	else
		curl --proto '=https' --proto-redir '=https' "$@"
	fi
}

amicus_install_traps() {
	trap 'amicus_cleanup' EXIT
	trap 'amicus_signal_cleanup 130' INT
	trap 'amicus_signal_cleanup 143' TERM
	trap 'amicus_signal_cleanup 129' HUP
}

amicus_cleanup() {
	status=$?
	if [ -n "${amicus_download_dir:-}" ] && [ -d "$amicus_download_dir" ]; then
		rm -rf "$amicus_download_dir"
	fi
	amicus_native_cleanup
	amicus_restore_terminal
	return "$status"
}

amicus_signal_cleanup() {
	amicus_restore_terminal
	exit "$1"
}

amicus_restore_terminal() {
	if [ "${amicus_screen_enabled:-0}" = 1 ]; then
		if ( : <>/dev/tty ) 2>/dev/null; then
			printf '%s%s' "$amicus_reset" "$amicus_show_cursor" >/dev/tty
		else
			printf '%s%s' "$amicus_reset" "$amicus_show_cursor" >&2
		fi
	fi
}

amicus_init_screen() {
	if [ "${AMICUS_INSTALLER_PLAIN:-0}" = 1 ]; then
		return
	fi
	if [ ! -t 1 ]; then
		return
	fi
	if [ "${TERM:-}" = dumb ]; then
		return
	fi
	amicus_screen_enabled=1
}

amicus_read_terminal_size() {
	amicus_screen_cols=80
	amicus_screen_rows=24

	if size=$(stty size 2>/dev/null </dev/tty); then
		set -- $size
		if [ "${1:-}" ] && [ "${2:-}" ]; then
			case "$1" in *[!0-9]*|"") ;; *) amicus_screen_rows="$1" ;; esac
			case "$2" in *[!0-9]*|"") ;; *) amicus_screen_cols="$2" ;; esac
		fi
	fi

	if [ "$amicus_screen_cols" -lt 1 ]; then
		amicus_screen_cols=80
	fi
	if [ "$amicus_screen_rows" -lt 1 ]; then
		amicus_screen_rows=24
	fi
}

amicus_screen() {
	if [ "$amicus_screen_enabled" != 1 ]; then
		return
	fi

	amicus_screen_title="${2:-$1}"
	if [ -z "$amicus_screen_title" ]; then
		amicus_screen_title="$1"
	fi
	amicus_screen_status=
	amicus_screen_detail="${3:-}"
	amicus_screen_question="${4:-}"
	amicus_screen_frame=$((amicus_screen_frame + 1))
	amicus_read_terminal_size
	amicus_init_screen_layout
	amicus_refresh_screen_layout_mode

	if [ "$amicus_screen_drawn" = 0 ] ||
		[ "$amicus_screen_cols" -ne "$amicus_screen_last_cols" ] ||
		[ "$amicus_screen_rows" -ne "$amicus_screen_last_rows" ]; then
		amicus_screen_prefix="${amicus_reset}${amicus_clear_screen}${amicus_hide_cursor}"
		amicus_screen_drawn=1
		amicus_screen_last_cols="$amicus_screen_cols"
		amicus_screen_last_rows="$amicus_screen_rows"
	else
		amicus_screen_prefix="${amicus_reset}${amicus_home_cursor}${amicus_hide_cursor}"
	fi
	amicus_screen_frame_text=$(amicus_render_screen)

	if ( : <>/dev/tty ) 2>/dev/null; then
		printf '%s%s%s%s' "$amicus_sync_start" "$amicus_screen_prefix" "$amicus_screen_frame_text" "$amicus_sync_end" >/dev/tty
	else
		printf '%s%s%s%s' "$amicus_sync_start" "$amicus_screen_prefix" "$amicus_screen_frame_text" "$amicus_sync_end" >&2
	fi
}

amicus_init_screen_layout() {
	if [ "$amicus_screen_layout_ready" = 1 ]; then
		return
	fi

	amicus_screen_layout_ready=1
	amicus_screen_layout_show_logo=0
	amicus_screen_layout_lab_width=0
	amicus_screen_render_lab_width=0
	if amicus_terminal_size_supports_logo; then
		amicus_screen_layout_show_logo=1
		amicus_screen_layout_lab_width=$(amicus_lab_width_for_cols "$amicus_screen_cols")
	fi
}

amicus_refresh_screen_layout_mode() {
	amicus_screen_compact=0
	amicus_screen_render_lab_width=0
	if [ "$amicus_screen_layout_show_logo" != 1 ]; then
		return
	fi
	if [ "$amicus_screen_rows" -lt 17 ]; then
		amicus_screen_compact=1
		return
	fi

	max_safe_width=$((amicus_screen_cols - 1))
	if [ "$max_safe_width" -lt 32 ]; then
		amicus_screen_compact=1
		return
	fi

	amicus_screen_render_lab_width="$amicus_screen_layout_lab_width"
	if [ "$amicus_screen_render_lab_width" -gt "$max_safe_width" ]; then
		amicus_screen_render_lab_width="$max_safe_width"
	fi
}

amicus_terminal_size_supports_logo() {
	[ "$amicus_screen_rows" -ge 22 ] && [ "$amicus_screen_cols" -ge 42 ]
}

amicus_lab_width_for_cols() {
	cols="$1"
	width=$((cols - 6))
	if [ "$width" -gt 78 ]; then
		width=78
	fi
	if [ "$width" -lt 42 ]; then
		width=42
	fi
	max_safe_width=$((cols - 1))
	if [ "$max_safe_width" -lt 1 ]; then
		max_safe_width=1
	fi
	if [ "$width" -gt "$max_safe_width" ]; then
		width="$max_safe_width"
	fi
	if [ "$width" -lt 32 ]; then
		width=32
	fi
	printf '%s' "$width"
}

amicus_render_screen() {
	content_height=$(amicus_content_height)
	top=$(((amicus_screen_rows - content_height) / 2))
	if [ "$top" -lt 0 ]; then
		top=0
	fi

	y=0
	while [ "$y" -lt "$amicus_screen_rows" ]; do
		content_index=$((y - top))
		amicus_content_line "$content_index"
		if [ "${amicus_content_is_set:-0}" = 1 ]; then
			amicus_print_centered_line "$amicus_content_text" "$amicus_content_width" "$amicus_content_style"
		else
			amicus_print_centered_line "" 0 ""
		fi
		y=$((y + 1))
	done
}

amicus_content_height() {
	height=2
	if amicus_show_logo; then
		height=$((height + 15))
	fi
	printf '%s' "$height"
}

amicus_show_logo() {
	[ "$amicus_screen_layout_show_logo" = 1 ] && [ "$amicus_screen_compact" != 1 ] && [ "$amicus_screen_render_lab_width" -ge 32 ]
}

amicus_content_line() {
	index="$1"
	amicus_content_is_set=0
	amicus_content_text=
	amicus_content_width=0
	amicus_content_style=

	if amicus_show_logo; then
		case "$index" in
			0|1|2|3|4|5|6|7|8|9|10|11|12|13) amicus_set_lab_line "$index" ;;
			14) amicus_set_blank_line ;;
		esac
		if [ "$amicus_content_is_set" = 1 ]; then
			return
		fi
		index=$((index - 15))
	fi

	if [ "$index" -lt 0 ]; then
		return
	fi

	if [ "$index" -eq 0 ]; then
		if [ -n "$amicus_screen_question" ]; then
			amicus_set_text_line "$(amicus_screen_primary_text)" "$amicus_bold$amicus_color_text"
		else
			amicus_set_title_line "$amicus_screen_title"
		fi
		return
	fi

	if [ "$index" -eq 1 ]; then
		if [ -n "$amicus_screen_question" ]; then
			amicus_set_text_line "Press Enter to continue; type n to cancel." "$amicus_color_muted"
		elif [ -n "$amicus_screen_detail" ]; then
			amicus_set_text_line "$amicus_screen_detail" "$amicus_color_muted"
		else
			amicus_set_blank_line
		fi
		return
	fi
}

amicus_screen_primary_text() {
	if [ -z "$amicus_screen_question" ]; then
		printf '%s' "$amicus_screen_title"
		return
	fi

	case "$amicus_screen_question" in
		*'[Y/n]'*) printf '%s [Y/n] >' "$amicus_screen_title" ;;
		*) printf '%s %s' "$amicus_screen_title" "$amicus_screen_question" ;;
	esac
}

amicus_set_lab_line() {
	lab_row="$1"
	amicus_lab_width="$amicus_screen_render_lab_width"

	logo_line=$(amicus_logo_line "$lab_row")
	if [ -n "$logo_line" ]; then
		logo_start=$(((amicus_lab_width - 32) / 2))
		logo_end=$((logo_start + 32))
		left=$(amicus_lab_background_range "$lab_row" 0 "$logo_start")
		right=$(amicus_lab_background_range "$lab_row" "$logo_end" "$amicus_lab_width")
		trace="${left}${amicus_color_text}${logo_line}${amicus_reset}${right}"
	else
		trace=$(amicus_lab_background_range "$lab_row" 0 "$amicus_lab_width")
	fi

	amicus_content_is_set=1
	amicus_content_text="$trace"
	amicus_content_width="$amicus_lab_width"
	amicus_content_style=
}

amicus_logo_line() {
	case "$1" in
		2) printf '                          ▄▄███▀' ;;
		3) printf '    ▄▄▄▄▄              ▄█████▀' ;;
		4) printf '    ██████▄         ▄██████▀' ;;
		5) printf '   ▄███▀███▄     ▄███▀▄██▀' ;;
		6) printf '   ███ ▄████▄▄▄████▀▄▄██' ;;
		7) printf '  ▀██  ▀█████████▀▀▀▀▀▀' ;;
		8) printf '  ▄██   ██████▀▀ ▄███' ;;
		9) printf ' █████    ▀█▄▄▄█████▀' ;;
		10) printf '███████▄  ████████▀' ;;
		11) printf '▀███▀▀    █████▀' ;;
	esac
}

amicus_lab_background_range() {
	lab_row="$1"
	range_start="$2"
	range_end="$3"
	active_style=
	line=
	x="$range_start"
	while [ "$x" -lt "$range_end" ]; do
		amicus_lab_cell "$x" "$lab_row"
		if [ "$amicus_lab_cell_style" != "$active_style" ]; then
			if [ -n "$active_style" ]; then
				line="${line}${amicus_reset}"
			fi
			if [ -n "$amicus_lab_cell_style" ]; then
				line="${line}${amicus_lab_cell_style}"
			fi
			active_style="$amicus_lab_cell_style"
		fi
		line="${line}${amicus_lab_cell_char}"
		x=$((x + 1))
	done
	if [ -n "$active_style" ]; then
		line="${line}${amicus_reset}"
	fi
	printf '%s' "$line"
}

amicus_lab_cell() {
	x="$1"
	y="$2"
	width="$amicus_lab_width"
	height=14
	frame="$amicus_screen_frame"
	amicus_lab_cell_char=" "
	amicus_lab_cell_style=

	hash=$(((x * 37 + y * 53 + frame * 11 + x * y * 3) % 101))
	if [ "$hash" -lt 3 ]; then
		amicus_lab_cell_char="·"
		amicus_lab_cell_style="$amicus_color_dim"
	fi

	center_x=$((width * 36 / 100))
	center_y=$((height * 54 / 100))
	dx=$((x - center_x))
	dy=$((y - center_y))
	if [ "$dx" -lt 0 ]; then
		dx=$((-dx))
	fi
	if [ "$dy" -lt 0 ]; then
		dy=$((-dy))
	fi
	contour=$((dx + dy * 4 + x / 6 - frame))
	if [ "$x" -lt $((width * 82 / 100)) ] && [ $(((contour % 24 + 24) % 24)) -eq 12 ]; then
		if [ $(((x + y) % 5)) -eq 0 ]; then
			amicus_lab_cell_char="╌"
		else
			amicus_lab_cell_char="·"
		fi
		amicus_lab_cell_style="$amicus_color_dim"
	fi

	horizon_y=$((height * 58 / 100))
	if [ "$y" -eq "$horizon_y" ] && [ $((x % 2)) -eq 0 ] && [ $(((x + frame) % 13)) -lt 2 ]; then
		amicus_lab_cell_char="─"
		if [ "$x" -gt $((width * 60 / 100)) ]; then
			amicus_lab_cell_style="$amicus_color_primary"
		else
			amicus_lab_cell_style="$amicus_color_dim"
		fi
	fi

	scan_start=$((width / 2))
	if [ "$x" -ge "$scan_start" ]; then
		scan_offset=$((x - scan_start))
		if [ $((scan_offset % 5)) -eq 0 ]; then
			scan_index=$((scan_offset / 5))
			scan_top=$((1 + (scan_index + frame / 3) % 3))
			scan_bottom=$((height - 2 - (scan_index * 2 + frame / 4) % 3))
			if [ "$y" -ge "$scan_top" ] && [ "$y" -le "$scan_bottom" ] && [ $(((y + scan_index + frame) % 6)) -ne 0 ]; then
				if [ $(((scan_index + y) % 4)) -eq 0 ]; then
					amicus_lab_cell_char="┃"
				else
					amicus_lab_cell_char="╎"
				fi
				amicus_lab_cell_style="$amicus_color_scan"
			fi
		fi
	fi

	trace_index=0
	while [ "$trace_index" -lt 3 ]; do
		case "$trace_index" in
			0) base=$((height * 30 / 100)) ;;
			1) base=$((height * 49 / 100)) ;;
			*) base=$((height * 72 / 100)) ;;
		esac
		wave=$(((x * 2 + frame + trace_index * 7) % 16))
		if [ "$wave" -gt 7 ]; then
			wave=$((15 - wave))
		fi
		trace_y=$((base + (wave - 3) / 2))
		if [ "$y" -eq "$trace_y" ]; then
			if [ $(((x + frame + trace_index * 13) % 41)) -eq 0 ]; then
				amicus_lab_cell_char="◆"
				amicus_lab_cell_style="$amicus_color_warning"
			elif [ $(((x + frame) % 12)) -eq 0 ]; then
				amicus_lab_cell_char="•"
				amicus_lab_cell_style="$amicus_color_primary"
			else
				amicus_lab_cell_char="·"
				amicus_lab_cell_style="$amicus_color_primary"
			fi
		fi
		trace_index=$((trace_index + 1))
	done
}

amicus_set_blank_line() {
	amicus_content_is_set=1
	amicus_content_text=
	amicus_content_width=0
	amicus_content_style=
}

amicus_set_text_line() {
	max_width=$((amicus_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	amicus_content_text=$(amicus_fit_ascii "$1" "$max_width")
	amicus_content_width=${#amicus_content_text}
	amicus_content_style="$2"
	amicus_content_is_set=1
}

amicus_set_title_line() {
	max_width=$((amicus_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	amicus_content_text=$(amicus_fit_ascii "$1" "$max_width")
	amicus_content_width=${#amicus_content_text}
	case "$amicus_content_text" in
		*"Amicus"*)
			amicus_content_text=$(amicus_style_amicus_title "$amicus_content_text")
			amicus_content_style=
			;;
		*)
			amicus_content_style="$amicus_bold$amicus_color_primary"
			;;
	esac
	amicus_content_is_set=1
}

amicus_style_amicus_title() {
	text="$1"
	styled=
	while :; do
		case "$text" in
			*"Amicus"*)
				before=${text%%Amicus*}
				rest=${text#*Amicus}
				styled="${styled}${amicus_bold}${amicus_color_primary}${before}"
				styled="${styled}${amicus_bold}${amicus_color_primary}Amicus${amicus_reset}"
				text="$rest"
				;;
			*)
				styled="${styled}${amicus_bold}${amicus_color_primary}${text}${amicus_reset}"
				printf '%s' "$styled"
				return
				;;
		esac
	done
}

amicus_fit_ascii() {
	text="$1"
	max_width="$2"
	if [ "${#text}" -le "$max_width" ]; then
		printf '%s' "$text"
		return
	fi
	if [ "$max_width" -le 3 ]; then
		printf '%s' "$text" | cut -c 1-"$max_width"
		return
	fi
	cut_width=$((max_width - 3))
	printf '%s...' "$(printf '%s' "$text" | cut -c 1-"$cut_width")"
}

amicus_print_centered_line() {
	text="$1"
	width="$2"
	style="$3"
	left=$(((amicus_screen_cols - width) / 2))
	if [ "$left" -lt 0 ]; then
		left=0
	fi
	if [ -n "$style" ]; then
		printf '%*s%s%s%s%s\n' "$left" "" "$style" "$text" "$amicus_reset" "$amicus_clear_line"
	else
		printf '%*s%s%s\n' "$left" "" "$text" "$amicus_clear_line"
	fi
}

amicus_place_prompt_cursor() {
	max_width=$((amicus_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	prompt_text=$(amicus_fit_ascii "$(amicus_screen_primary_text)" "$max_width")
	prompt_width=${#prompt_text}
	content_height=$(amicus_content_height)
	top=$(((amicus_screen_rows - content_height) / 2))
	if [ "$top" -lt 0 ]; then
		top=0
	fi
	prompt_index=0
	if amicus_show_logo; then
		prompt_index=$((prompt_index + 15))
	fi
	row=$((top + prompt_index + 1))
	col=$(((amicus_screen_cols - prompt_width) / 2 + prompt_width + 2))
	if [ "$col" -lt 1 ]; then
		col=1
	fi
	if [ "$col" -gt "$amicus_screen_cols" ]; then
		col="$amicus_screen_cols"
	fi
	if ( : <>/dev/tty ) 2>/dev/null; then
		printf '%s%s%s[%s;%sH' "$amicus_reset" "$amicus_show_cursor" "$amicus_esc" "$row" "$col" >/dev/tty
	else
		printf '%s%s%s[%s;%sH' "$amicus_reset" "$amicus_show_cursor" "$amicus_esc" "$row" "$col" >&2
	fi
}

amicus_pulse() {
	case $((amicus_screen_frame % 4)) in
		0) printf '.' ;;
		1) printf '..' ;;
		2) printf '...' ;;
		*) printf '' ;;
	esac
}

amicus_animation_detail_count() {
	details="$1"
	case "$details" in
		*'
'*) printf '%s\n' "$details" | wc -l | tr -d ' ' ;;
		*) printf '1' ;;
	esac
}

amicus_animation_current_frame() {
	frame="${amicus_animation_frame:-1}"
	case "$frame" in
		""|*[!0-9]*) frame=1 ;;
	esac
	if [ "$frame" -lt 1 ]; then
		frame=1
	fi
	printf '%s' "$frame"
}

amicus_animation_step_index() {
	details="$1"
	detail_count=$(amicus_animation_detail_count "$details")
	frame=$(amicus_animation_current_frame)
	detail_index=$(((frame - 1) / 24 + 1))
	if [ "$detail_index" -gt "$detail_count" ]; then
		detail_index="$detail_count"
	fi
	printf '%s' "$detail_index"
}

amicus_static_progress_title() {
	case "$1" in
		*...) printf '%s' "$1" ;;
		*) printf '%s...' "$1" ;;
	esac
}

amicus_animation_status() {
	status="$1"
	details="$2"
	status_mode="$3"
	case "$status_mode" in
		static) amicus_static_progress_title "$status" ;;
		*) printf '%s%s' "$status" "$(amicus_pulse)" ;;
	esac
}

amicus_animation_detail() {
	details="$1"
	case "$details" in
		*'
'*)
			detail_index=$(amicus_animation_step_index "$details")
			printf '%s\n' "$details" | sed -n "${detail_index}p"
			;;
		*) printf '%s' "$details" ;;
	esac
}

amicus_run_quiet_with_animation() {
	title="$1"
	status="$2"
	detail="$3"
	shift 3

	amicus_run_quiet_with_animation_command "$title" "$status" "$detail" pulse "$@"
}

amicus_run_quiet_with_animation_steps() {
	title="$1"
	status="$2"
	details="$3"
	shift 3

	amicus_run_quiet_with_animation_command "$title" "$status" "$details" static "$@"
}

amicus_run_quiet_with_animation_command() {
	title="$1"
	status="$2"
	details="$3"
	status_mode="$4"
	shift 4

	if [ "$amicus_screen_enabled" != 1 ]; then
		printf '%s\n' "$status" >&2
		"$@"
		return
	fi

	output_dir=$(create_temp_dir)
	output_file="$output_dir/output"
	"$@" >"$output_file" 2>&1 &
	command_pid=$!
	amicus_animation_frame=0

	while kill -0 "$command_pid" 2>/dev/null; do
		amicus_animation_frame=$((amicus_animation_frame + 1))
		status_display=$(amicus_animation_status "$status" "$details" "$status_mode")
		amicus_screen "$title" "$status_display" "$(amicus_animation_detail "$details")" ""
		sleep 0.18
	done

	if wait "$command_pid"; then
		command_status=0
	else
		command_status=$?
	fi

	if [ "$command_status" -ne 0 ] && [ -s "$output_file" ]; then
		amicus_restore_terminal
		printf '\n' >&2
		cat "$output_file" >&2
	fi
	rm -rf "$output_dir"
	return "$command_status"
}

amicus_prompt_yes_no() {
	question="$1"
	detail="$2"
	input_prompt="$3"

	if ( : <>/dev/tty ) 2>/dev/null; then
		prompt_input=tty
		exec 3<>/dev/tty
	elif [ -t 0 ]; then
		prompt_input=stdin
	else
		return 2
	fi

	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "$question" "" "$detail" "$input_prompt"
		amicus_place_prompt_cursor "$input_prompt"
	else
		printf '%s\n' "$detail"
		if [ "$prompt_input" = tty ]; then
			printf '%s ' "$input_prompt" >&3
		else
			printf '%s ' "$input_prompt" >&2
		fi
	fi

	if [ "$prompt_input" = tty ]; then
		if ! IFS= read -r answer <&3; then
			answer=
		fi
		exec 3>&-
	else
		if ! IFS= read -r answer; then
			answer=
		fi
	fi

	case "$answer" in
		n|N|no|NO)
			return 1
			;;
	esac
	return 0
}

start_preflight_checks() {
	preflight_dir=$(create_temp_dir)
	preflight_file="$preflight_dir/preflight"
	run_preflight_checks >"$preflight_file" &
	preflight_pid=$!
}

finish_preflight_checks() {
	if [ "$amicus_screen_enabled" = 1 ]; then
		while kill -0 "$preflight_pid" 2>/dev/null; do
			amicus_screen "Checking Node.js and npm$(amicus_pulse)" "" "" ""
			sleep 0.18
		done
	fi

	if wait "$preflight_pid"; then
		preflight_status=0
	else
		preflight_status=$?
	fi

	if [ "$amicus_screen_enabled" = 1 ]; then
		if [ "$preflight_status" -ne 0 ]; then
			preflight_summary=$(sed -n '1p' "$preflight_file")
			amicus_screen "Node.js 20.6.0 or newer is required" "" "$preflight_summary" ""
			sleep 0.4
		elif [ -s "$preflight_file" ]; then
			preflight_summary="Existing $amicus_cmd command found on PATH."
			amicus_screen "Environment ready" "" "$preflight_summary" ""
			sleep 0.4
		fi
	else
		cat "$preflight_file"
	fi
	rm -rf "$preflight_dir"
	return "$preflight_status"
}

run_preflight_checks() {
	status=0
	yellow="${amicus_esc}[33m"
	reset="${amicus_esc}[0m"

	if command -v node >/dev/null 2>&1; then
		node_version=$(node --version)
		if ! node -e 'const [major, minor, patch] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && (minor > 6 || (minor === 6 && patch >= 0))) ? 0 : 1)' >/dev/null; then
			printf 'error: Amicus requires Node.js 20.6.0 or newer. Found %s.\n' "$node_version"
			status=1
		fi
	else
		printf 'error: Node.js 20.6.0 or newer is required to install Amicus.\n'
		status=1
	fi

	if ! command -v npm >/dev/null 2>&1; then
		printf 'error: npm is required to install Amicus.\n'
		status=1
	fi

	if [ "$status" -ne 0 ]; then
		printf '\n'
	fi

	if amicus_path=$(command -v "$amicus_cmd" 2>/dev/null); then
		printf '%sExisting %s found at: %s%s\n' "$yellow" "$amicus_cmd" "$amicus_path" "$reset"
		printf '\n'
	fi

	return "$status"
}

resolve_amicus_version() {
	if [ "${1:-}" ]; then
		case "$1" in
			stable|beta) release_channel="$1" ;;
			*)
				normalize_version "$1"
				return
				;;
		esac
	else
		release_channel="$amicus_release_channel"
	fi

	if [ "${AMICUS_VERSION:-}" ]; then
		normalize_version "$AMICUS_VERSION"
		return
	fi

	if ! command -v curl >/dev/null 2>&1; then
		printf 'error: curl is required to resolve the latest Amicus version.\n' >&2
		exit 1
	fi

	case "$release_channel" in
		stable|beta) ;;
		*)
			printf 'error: invalid Amicus release channel: %s\n' "$release_channel" >&2
			exit 1
			;;
	esac

	channel_dir=$(create_temp_dir)
	channel_path="$channel_dir/$release_channel"
	if ! amicus_run_quiet_with_animation \
		"Resolving latest release" \
		"Resolving latest release" \
		"Checking the $release_channel release channel." \
		amicus_curl_download -fsSL "$amicus_base_url/$release_channel" -o "$channel_path"; then
		rm -rf "$channel_dir"
		printf 'error: could not resolve latest Amicus version from %s/%s\n' "$amicus_base_url" "$release_channel" >&2
		exit 1
	fi
	channel_version="$(tr -d '[:space:]' <"$channel_path")"
	rm -rf "$channel_dir"
	if [ -z "$channel_version" ]; then
		printf 'error: could not resolve latest Amicus version from %s/%s\n' "$amicus_base_url" "$release_channel" >&2
		exit 1
	fi
	normalize_version "$channel_version"
}

normalize_version() {
	version="${1#v}"
	case "$version" in
		"")
			printf 'error: empty Amicus version.\n' >&2
			exit 1
			;;
		*[!0-9A-Za-z.-]*)
			printf 'error: invalid Amicus version: %s\n' "$1" >&2
			exit 1
			;;
	esac
	printf '%s' "$version"
}

install_node_npm_interactive() {
	method=$(detect_node_install_method)
	case "$method" in
		homebrew) label="Homebrew" ;;
		apt) label="apt" ;;
		apk) label="apk" ;;
		standalone) label="standalone Node.js" ;;
		*)
			method=standalone
			label="standalone Node.js"
			;;
	esac

	if amicus_prompt_yes_no \
		"Install Node.js and npm with $label?" \
		"Required before Amicus can be installed." \
		"Install? [Y/n]"; then
		install_node_npm "$method" "$label"
		return
	else
		prompt_status=$?
	fi
	if [ "$prompt_status" -eq 2 ]; then
		printf 'No terminal detected; install Node.js 20.6.0 or newer and npm, then run this installer again.\n'
	else
		printf '\nInstall Node.js 20.6.0 or newer and npm, then run this installer again.\n'
	fi
	return 1
}

detect_node_install_method() {
	case "$(uname -s)" in
		Darwin)
			if command -v brew >/dev/null 2>&1; then
				printf 'homebrew'
			else
				printf 'standalone'
			fi
			;;
		Linux)
			if command -v apt-cache >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1 && apt_node_candidate_is_new_enough; then
				printf 'apt'
			elif command -v apk >/dev/null 2>&1 && apk_node_candidate_is_new_enough; then
				printf 'apk'
			else
				printf 'standalone'
			fi
			;;
		*)
			printf 'standalone'
			;;
	esac
}

apt_node_candidate_is_new_enough() {
	version=$(apt-cache policy nodejs 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
	[ -n "$version" ] && [ "$version" != "(none)" ] && node_version_string_is_new_enough "$version"
}

apk_node_candidate_is_new_enough() {
	version=$(apk search -x nodejs 2>/dev/null | awk -F- '/^nodejs-/ { print $2; exit }')
	[ -n "$version" ] && node_version_string_is_new_enough "$version"
}

node_version_string_is_new_enough() {
	version="${1#v}"
	case "$version" in
		[0-9]*) ;;
		*) return 1 ;;
	esac
	version="${version%%[!0-9.]*}"
	version_ifs=${IFS- }
	IFS=.
	set -- $version
	IFS=$version_ifs
	major="${1:-}"
	minor="${2:-0}"
	patch="${3:-0}"
	case "$major" in ''|*[!0-9]*) return 1 ;; esac
	case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
	case "$patch" in ''|*[!0-9]*) patch=0 ;; esac

	[ "$major" -gt 20 ] && return 0
	[ "$major" -eq 20 ] && [ "$minor" -gt 6 ] && return 0
	[ "$major" -eq 20 ] && [ "$minor" -eq 6 ] && [ "$patch" -ge 0 ] && return 0
	return 1
}

install_node_npm() {
	method="$1"
	label="$2"

	if [ "$amicus_screen_enabled" != 1 ]; then
		printf '\nInstalling Node.js and npm with %s...\n\n' "$label"
		run_node_install_method "$method"
	else
		prepare_sudo_for_node_install "$method"
		node_install_details="Using $label.
Resolving Node.js packages.
Downloading Node.js runtime.
Installing npm.
Preparing Amicus setup."
		amicus_run_quiet_with_animation_steps \
			"Installing Node.js and npm" \
			"Installing Node.js and npm" \
			"$node_install_details" \
			run_node_install_method "$method"
	fi

	if [ "$method" = standalone ]; then
		load_standalone_node
		AMICUS_NODE_INSTALLED_STANDALONE=1
	fi
	hash -r
	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "Node.js and npm installed" "" "Continuing Amicus setup." ""
	else
		printf '\nNode.js and npm are installed.\n\n'
	fi
}

node_install_needs_sudo() {
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		return 1
	fi

	case "$1" in
		apt|apk)
			return 0
			;;
		standalone)
			[ "$(uname -s)" = Linux ] || return 1
			command -v xz >/dev/null 2>&1 && return 1
			command -v apt-get >/dev/null 2>&1 || command -v apk >/dev/null 2>&1
			;;
		*)
			return 1
			;;
	esac
}

prepare_sudo_for_node_install() {
	method="$1"
	if ! node_install_needs_sudo "$method"; then
		return 0
	fi

	amicus_screen "Preparing Node.js install" "" "This may ask for your sudo password." ""
	amicus_restore_terminal
	printf '\n'
	sudo -v
}

run_node_install_method() {
	case "$1" in
		homebrew) install_node_with_homebrew ;;
		apt) install_node_with_apt ;;
		apk) install_node_with_apk ;;
		standalone) install_node_standalone ;;
	esac
}

install_node_with_homebrew() {
	if brew list node >/dev/null 2>&1; then
		brew upgrade node
	else
		brew install node
	fi
}

install_node_with_apt() {
	print_sudo_note
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		apt-get update
		apt-get install -y nodejs npm
	else
		sudo sh -c 'apt-get update && apt-get install -y nodejs npm'
	fi
}

install_node_with_apk() {
	print_sudo_note
	run_with_sudo apk add --update-cache nodejs npm
}

install_node_standalone() {
	node_platform=$(detect_node_binary_platform) || {
		printf 'Unsupported operating system for automatic Node.js install: %s\n' "$(uname -s)"
		return 1
	}
	node_arch=$(detect_node_binary_arch) || {
		printf 'Unsupported CPU architecture for automatic Node.js install: %s\n' "$(uname -m)"
		return 1
	}
	node_dist_base="https://nodejs.org/dist/latest-v22.x"
	node_base_dir=$(node_standalone_base_dir)
	node_tmp_dir=$(create_temp_dir)

	mkdir -p "$node_tmp_dir" "$node_base_dir"

	printf 'Resolving Node.js binary for %s-%s\n' "$node_platform" "$node_arch"
	amicus_curl_download -fsSL "$node_dist_base/SHASUMS256.txt" -o "$node_tmp_dir/SHASUMS256.txt"
	node_file=$(awk -v suffix="-$node_platform-$node_arch.tar.xz" '
		index($2, "node-v") == 1 && length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }
	' "$node_tmp_dir/SHASUMS256.txt")
	if [ -z "$node_file" ]; then
		printf 'No Node.js binary is available for %s-%s.\n' "$node_platform" "$node_arch"
		rm -rf "$node_tmp_dir"
		return 1
	fi
	case "$node_file" in
		*/*|*\\*|*..*)
			printf 'Unsafe Node.js archive name in checksum manifest: %s\n' "$node_file"
			rm -rf "$node_tmp_dir"
			return 1
			;;
		node-v*-"$node_platform"-"$node_arch".tar.xz) ;;
		*)
			printf 'Unexpected Node.js archive name in checksum manifest: %s\n' "$node_file"
			rm -rf "$node_tmp_dir"
			return 1
			;;
	esac

	printf 'Downloading Node.js %s\n' "${node_file%.tar.xz}"
	amicus_curl_download -fsSL "$node_dist_base/$node_file" -o "$node_tmp_dir/$node_file"
	verify_node_standalone_download "$node_tmp_dir" "$node_file"
	ensure_node_standalone_extract_tools "$node_platform"

	node_dir="$node_base_dir/${node_file%.tar.xz}"
	rm -rf "$node_dir"
	printf 'Extracting Node.js to %s\n' "$node_dir"
	tar -xf "$node_tmp_dir/$node_file" -C "$node_base_dir"
	rm -f "$node_base_dir/current"
	ln -s "$node_dir" "$node_base_dir/current"
	rm -rf "$node_tmp_dir"
	printf 'Node.js installed at %s\n' "$node_dir"
}

verify_node_standalone_download() {
	checksum_dir="$1"
	checksum_file_name="$2"
	awk -v file="$checksum_file_name" '$2 == file { print }' "$checksum_dir/SHASUMS256.txt" >"$checksum_dir/SHASUMS256.selected"

	if command -v sha256sum >/dev/null 2>&1; then
		printf 'Verifying Node.js download\n'
		(cd "$checksum_dir" && sha256sum -c SHASUMS256.selected)
	elif command -v shasum >/dev/null 2>&1; then
		printf 'Verifying Node.js download\n'
		(cd "$checksum_dir" && shasum -a 256 -c SHASUMS256.selected)
	else
		printf 'error: sha256sum or shasum is required to verify the Node.js download.\n'
		return 1
	fi
}

ensure_node_standalone_extract_tools() {
	extract_platform="$1"

	if [ "$extract_platform" = linux ] && ! command -v xz >/dev/null 2>&1; then
		printf 'Installing xz-utils for Node.js archive extraction\n'
		print_sudo_note
		if command -v apt-get >/dev/null 2>&1; then
			run_with_sudo apt-get update
			run_with_sudo apt-get install -y xz-utils
		elif command -v apk >/dev/null 2>&1; then
			run_with_sudo apk add --update-cache xz
		else
			printf 'xz is required to extract Node.js. Install xz and run this installer again.\n'
			return 1
		fi
	fi
}

load_standalone_node() {
	AMICUS_STANDALONE_NODE_BIN="$(node_standalone_base_dir)/current/bin"
	PATH="$AMICUS_STANDALONE_NODE_BIN:$PATH"
	export AMICUS_STANDALONE_NODE_BIN PATH
}

node_standalone_base_dir() {
	if [ -n "${XDG_DATA_HOME:-}" ]; then
		printf '%s/amicus-node' "$XDG_DATA_HOME"
	else
		printf '%s/.local/share/amicus-node' "$HOME"
	fi
}

detect_node_binary_platform() {
	case "$(uname -s)" in
		Darwin) printf 'darwin' ;;
		Linux) printf 'linux' ;;
		*) return 1 ;;
	esac
}

detect_node_binary_arch() {
	case "$(uname -m)" in
		x86_64|amd64) printf 'x64' ;;
		arm64|aarch64) printf 'arm64' ;;
		armv7l) printf 'armv7l' ;;
		ppc64le) printf 'ppc64le' ;;
		s390x) printf 's390x' ;;
		*) return 1 ;;
	esac
}

print_sudo_note() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		printf 'This may ask for your sudo password.\n\n'
	fi
}

run_with_sudo() {
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

configure_standalone_node_path() {
	if original_amicus_path=$(resolve_amicus_with_original_path); then
		case "$original_amicus_path" in
			"$AMICUS_STANDALONE_NODE_BIN/"*)
				if [ "$amicus_screen_enabled" = 1 ]; then
					amicus_screen "Amicus installed" "" "Run it with: $amicus_cmd" ""
				else
					printf '\nRun it with: %s\n' "$amicus_cmd"
				fi
				return 0
				;;
		esac
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_screen "Amicus installed" "" "PATH update needed for $amicus_cmd." ""
		else
			printf '%s was installed, but your shell is not using that install yet.\n' "$amicus_cmd"
			printf 'Your shell currently resolves %s to: %s\n' "$amicus_cmd" "$original_amicus_path"
		fi
	else
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_screen "Amicus installed" "" "PATH update needed for $amicus_cmd." ""
		else
			printf '%s was installed, but your shell is not using that install yet.\n' "$amicus_cmd"
		fi
	fi

	profile=$(detect_shell_profile) || {
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_restore_terminal
			printf '\n'
		fi
		print_standalone_path_manual_instructions
		return 0
	}

	if shell_profile_has_standalone_node_path "$profile"; then
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_screen "Amicus installed" "" "Run: $(amicus_source_profile_command "$profile")" ""
		else
			printf '%s already contains %s.\n' "$profile" "$AMICUS_STANDALONE_NODE_BIN"
			printf 'Restart your shell or run: %s\n' "$(amicus_source_profile_command "$profile")"
		fi
		return 0
	fi

	prompt_add_standalone_node_path "$profile"
}

resolve_amicus_with_original_path() {
	saved_path=$PATH
	PATH=$amicus_original_path
	if command -v "$amicus_cmd" 2>/dev/null; then
		status=0
	else
		status=$?
	fi
	PATH=$saved_path
	return "$status"
}

detect_shell_profile() {
	if [ -n "${AMICUS_SHELL_PROFILE:-}" ]; then
		printf '%s' "$AMICUS_SHELL_PROFILE"
		return 0
	fi
	if [ -z "${HOME:-}" ]; then
		return 1
	fi

	shell_name="${SHELL:-}"
	shell_name="${shell_name##*/}"
	case "$shell_name" in
		zsh)
			printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"
			;;
		bash)
			printf '%s/.bashrc' "$HOME"
			;;
		*)
			if [ -f "$HOME/.zshrc" ]; then
				printf '%s/.zshrc' "$HOME"
			elif [ -f "$HOME/.bashrc" ]; then
				printf '%s/.bashrc' "$HOME"
			else
				printf '%s/.profile' "$HOME"
			fi
			;;
	esac
}

shell_profile_has_standalone_node_path() {
	profile="$1"
	[ -f "$profile" ] && grep -F "$AMICUS_STANDALONE_NODE_BIN" "$profile" >/dev/null 2>&1
}

prompt_add_standalone_node_path() {
	profile="$1"
	path_line=$(standalone_node_path_line)

	if ! amicus_prompt_yes_no \
		"Add standalone Node.js to your PATH?" \
		"Updates $profile so future shells can run $amicus_cmd." \
		"Update PATH? [Y/n]"; then
		if [ "$amicus_screen_enabled" = 1 ]; then
			amicus_restore_terminal
			printf '\n'
		fi
		print_standalone_path_manual_instructions
		return 0
	fi

	mkdir -p "$(dirname "$profile")"
	{
		printf '\n# Amicus standalone Node.js\n'
		printf '%s\n' "$path_line"
	} >>"$profile"
	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "Amicus installed" "" "Run: $(amicus_source_profile_command "$profile")" ""
	else
		printf 'Added %s to %s.\n' "$AMICUS_STANDALONE_NODE_BIN" "$profile"
		printf 'Restart your shell or run: %s\n' "$(amicus_source_profile_command "$profile")"
	fi
}

print_standalone_path_manual_instructions() {
	printf 'Add this to your shell profile to use %s from new shells:\n\n' "$amicus_cmd"
	printf '  %s\n' "$(standalone_node_path_line)"
	printf '\nThen restart your shell and run: %s\n' "$amicus_cmd"
}

standalone_node_path_line() {
	printf 'export PATH="%s:$PATH"' "$AMICUS_STANDALONE_NODE_BIN"
}

amicus_shell_quote() {
	quoted=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
	printf "'%s'" "$quoted"
}

amicus_source_profile_command() {
	printf '. %s && %s' "$(amicus_shell_quote "$1")" "$amicus_cmd"
}

download_amicus_package() {
	version="$1"
	tarball_url="$2"
	tarball_path="$3"
	download_dir=$(dirname "$tarball_path")
	tarball_name=$(basename "$tarball_path")
	checksums_url="$amicus_base_url/releases/v$version/SHA256SUMS"
	checksums_path="$download_dir/SHA256SUMS"

	if ! command -v curl >/dev/null 2>&1; then
		printf 'error: curl is required to download Amicus.\n' >&2
		exit 1
	fi

	amicus_run_quiet_with_animation \
		"Downloading checksums" \
		"Downloading release checksums" \
		"Amicus v$version" \
		amicus_curl_download -fsSL "$checksums_url" -o "$checksums_path"

	amicus_run_quiet_with_animation \
		"Downloading Amicus" \
		"Downloading Amicus v$version" \
		"Fetching the checksummed package." \
		amicus_curl_download -fsSL "$tarball_url" -o "$tarball_path"

	verify_amicus_package_checksum "$checksums_path" "$tarball_path"
}

verify_amicus_package_checksum() {
	checksums_path="$1"
	tarball_path="$2"
	checksum_dir=$(dirname "$tarball_path")
	tarball_name=$(basename "$tarball_path")
	selected_checksums_path="$checksum_dir/SHA256SUMS.selected"

	if ! awk -v file="$tarball_name" '$2 == file { print; found = 1; exit } END { if (!found) exit 1 }' \
		"$checksums_path" >"$selected_checksums_path"; then
		printf 'error: checksum for %s was not found in %s\n' "$tarball_name" "$checksums_path" >&2
		exit 1
	fi

	if command -v sha256sum >/dev/null 2>&1; then
		amicus_run_quiet_with_animation \
			"Verifying download" \
			"Verifying Amicus download" \
			"Checking SHA-256." \
			amicus_run_checksum_check "$checksum_dir" "$(basename "$selected_checksums_path")" sha256sum
	elif command -v shasum >/dev/null 2>&1; then
		amicus_run_quiet_with_animation \
			"Verifying download" \
			"Verifying Amicus download" \
			"Checking SHA-256." \
			amicus_run_checksum_check "$checksum_dir" "$(basename "$selected_checksums_path")" shasum
	else
		printf 'error: sha256sum or shasum is required to verify the Amicus download.\n' >&2
		exit 1
	fi
}

amicus_run_checksum_check() {
	checksum_dir="$1"
	selected_checksums_name="$2"
	checker="$3"
	case "$checker" in
		sha256sum)
			(cd "$checksum_dir" && sha256sum -c "$selected_checksums_name")
			;;
		shasum)
			(cd "$checksum_dir" && shasum -a 256 -c "$selected_checksums_name")
			;;
	esac
}

confirm_install() {
	version="$1"
	tarball_url="$2"

	if amicus_prompt_yes_no \
		"Install Amicus v$version globally with npm?" \
		"Downloads the checksummed release and runs npm install -g." \
		"Install? [Y/n]"; then
		return 0
	else
		prompt_status=$?
	fi

	if [ "$prompt_status" -eq 2 ]; then
		printf 'This will download, verify, and install:\n\n  %s\n\n' "$tarball_url"
		printf 'No terminal detected; continuing without confirmation.\n'
		return 0
	fi

	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "Installation cancelled" "" "No changes were made." ""
		exit 0
	fi
	printf '\nInstallation cancelled.\n'
	exit 0
}

confirm_kernel_runtime_setup() {
	case "${AMICUS_BOOTSTRAP_KERNEL_ON_INSTALL:-}" in
		1)
			amicus_bootstrap_kernel_on_install=1
			return
			;;
		0)
			amicus_bootstrap_kernel_on_install=0
			return
			;;
	esac

	if amicus_prompt_yes_no \
		"Prepare Python runtime now?" \
		"Installs uv, Python 3.11, and the Amicus runtime." \
		"Prepare? [Y/n]"; then
		amicus_bootstrap_kernel_on_install=1
		return
	else
		prompt_status=$?
	fi

	if [ "$prompt_status" -eq 2 ]; then
		printf 'No terminal detected; preparing the Python runtime during install.\n'
		amicus_bootstrap_kernel_on_install=1
		return
	fi

	amicus_bootstrap_kernel_on_install=0
	if [ "$amicus_screen_enabled" = 1 ]; then
		amicus_screen "Python setup skipped" "" "The runtime can be prepared on first ipython use." ""
		sleep 0.4
	else
		printf '\nSkipping Python runtime setup.\n'
	fi
}

amicus_npm_requires_remote_policy() {
	npm_version=$(npm --version 2>/dev/null) || return 1
	npm_major=${npm_version%%.*}
	case "$npm_major" in
		""|*[!0-9]*) return 1 ;;
	esac
	[ "$npm_major" -ge 12 ]
}

amicus_npm_install() {
	tarball_path="$1"
	shift
	if amicus_npm_requires_remote_policy; then
		# Limit npm 12's required policy overrides to the verified root package.
		env "$@" npm install -g --no-fund --no-audit --loglevel=error --progress=false \
			--allow-remote=all --allow-scripts="$tarball_path" "$tarball_path"
	else
		env "$@" npm install -g --no-fund --no-audit --loglevel=error --progress=false "$tarball_path"
	fi
}

install_amicus_package() {
	tarball_path="$1"
	if [ "$amicus_bootstrap_kernel_on_install" = 1 ]; then
		npm_install_details="Preparing global install.
Linking command binaries.
Installing runtime packages.
Preloading search tools.
Preparing Python kernel.
Finalizing npm install."
		amicus_run_quiet_with_animation_steps \
			"Installing Amicus" \
			"Installing Amicus" \
			"$npm_install_details" \
			amicus_npm_install "$tarball_path" AMICUS_BOOTSTRAP_TOOLS_ON_INSTALL=1 AMICUS_BOOTSTRAP_KERNEL_ON_INSTALL=1 AMICUS_INSTALL_UV=1
	else
		npm_install_details="Preparing global install.
Linking command binaries.
Installing runtime packages.
Preloading search tools.
Finalizing npm install."
		amicus_run_quiet_with_animation_steps \
			"Installing Amicus" \
			"Installing Amicus" \
			"$npm_install_details" \
			amicus_npm_install "$tarball_path" AMICUS_BOOTSTRAP_TOOLS_ON_INSTALL=1
	fi
}

# Supported glibc releases carry no libc suffix; musl builds are published separately.
amicus_native_glibc() {
	native_glibc_version=$(getconf GNU_LIBC_VERSION 2>/dev/null) || return 1
	printf '%s\n' "$native_glibc_version" |
		awk '$1 == "glibc" { split($2, v, "."); if (v[1] > 2 || (v[1] == 2 && v[2] >= 17)) ok=1 } END { exit !ok }'
}

# Alpine and other musl distributions ship the loader under a fixed name; `ldd`
# without arguments prints its musl banner and is the fallback for stripped images.
amicus_native_musl() {
	for native_musl_loader in "$amicus_native_sysroot"/lib/ld-musl-*.so.1; do
		[ -e "$native_musl_loader" ] && return 0
	done
	ldd 2>&1 | grep -q musl
}

# Bun's default x64 build needs AVX2; hosts without it need the baseline build.
# An unreadable CPU inventory selects baseline, which runs on every x86-64 CPU.
amicus_native_avx2() {
	awk '/^flags[[:space:]]*:/ { for (i = 3; i <= NF; i++) if ($i == "avx2") found = 1 } END { exit !found }' \
		"$amicus_native_sysroot/proc/cpuinfo" 2>/dev/null
}

amicus_native_platform() {
	native_libc_suffix=
	case "$(uname -s)" in
		Darwin)
			native_os_version=$(sw_vers -productVersion) || return 1
			case "${native_os_version%%.*}" in ''|*[!0-9]*) return 1 ;; esac
			[ "${native_os_version%%.*}" -ge 13 ] || return 1
			native_os=darwin
			;;
		Linux)
			native_os=linux
			if amicus_native_glibc; then
				native_libc_suffix=
			elif amicus_native_musl; then
				native_libc_suffix=-musl
			else
				return 1
			fi
			;;
		*) return 1 ;;
	esac
	case "$(uname -m)" in
		arm64|aarch64) printf '%s-arm64%s' "$native_os" "$native_libc_suffix" ;;
		x86_64|amd64)
			if [ "$native_os" = linux ] && ! amicus_native_avx2; then
				printf '%s-x64%s-baseline' "$native_os" "$native_libc_suffix"
			else
				printf '%s-x64%s' "$native_os" "$native_libc_suffix"
			fi
			;;
		*) return 1 ;;
	esac
}

amicus_native_cleanup() {
	if [ -n "${amicus_native_lock:-}" ] && [ "$(cat "$amicus_native_lock/pid" 2>/dev/null || :)" = "$$" ] &&
		[ -n "${native_root:-}" ] && { [ -e "$native_root/.activation-state" ] || [ -L "$native_root/.activation-state" ]; }; then
		if amicus_native_recover_activation; then
			amicus_native_prune_releases
		else
			printf 'Could not recover the interrupted activation; inspect %s/.activation-state before retrying.\n' "$native_root" >&2
		fi
	fi
	if [ -n "${amicus_native_activation_target:-}" ] && [ -n "${amicus_native_activation_previous:-}" ] &&
		[ "$(readlink "$native_root/bin/amicus" 2>/dev/null || :)" = "$amicus_native_activation_target" ] &&
		[ "$(readlink "$native_root/bin/previous" 2>/dev/null || :)" != "$amicus_native_activation_previous" ]; then
		amicus_native_atomic_link "$amicus_native_activation_previous" "$native_root/bin/previous" ||
			printf 'Could not finish retaining the previous release; recover it from %s/releases.\n' "$native_root" >&2
	fi
	amicus_native_activation_target=
	amicus_native_activation_previous=
	if [ -n "${amicus_native_stage:-}" ]; then
		rm -rf "$amicus_native_stage"
		amicus_native_stage=
	fi
	if [ -n "${amicus_native_lock:-}" ] && [ "$(cat "$amicus_native_lock/pid" 2>/dev/null || :)" = "$$" ]; then
		rm -f "$amicus_native_lock/pid"
		rmdir "$amicus_native_lock"
	fi
	amicus_native_lock=
	amicus_native_discard_adopted_root
}

# A first install that never activated a release must not keep the ownership
# marker: the next run would find a managed tree holding no executable. Only a
# root this run created, still empty apart from what this run created, is given up.
amicus_native_discard_adopted_root() {
	[ "${amicus_native_root_adopted:-0}" = 1 ] || return 0
	amicus_native_root_adopted=0
	[ -n "${native_root:-}" ] || return 0
	if [ -e "$native_root/bin/amicus" ] || [ -L "$native_root/bin/amicus" ]; then return 0; fi
	[ -z "$(ls -A "$native_root" 2>/dev/null | grep -vxE '\.managed|bin|releases' || :)" ] || return 0
	rmdir "$native_root/bin" "$native_root/releases" 2>/dev/null || :
	if [ -e "$native_root/bin" ] || [ -e "$native_root/releases" ]; then return 0; fi
	rm -f "$native_root/.managed"
	rmdir "$native_root" 2>/dev/null || :
}

amicus_native_prepare_root() {
	native_root="${AMICUS_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/amicus}"
	case "$native_root" in /*) ;; *) printf 'error: install directory must be absolute.\n' >&2; exit 1 ;; esac
	mkdir -p "$native_root"
	native_root=$(CDPATH= cd "$native_root" && pwd -P)
	if [ -L "$native_root/.managed" ] || [ -L "$native_root/releases" ] || [ -L "$native_root/bin" ]; then
		printf 'error: managed installation directories must not be symlinks.\n' >&2; exit 1
	fi
	amicus_native_root_adopted=0
	if [ -e "$native_root/.managed" ]; then
		[ "$(cat "$native_root/.managed")" = amicus-native-v1 ] || {
			printf 'error: unrecognized installation owner in %s.\n' "$native_root" >&2; exit 1;
		}
	elif [ -n "$(ls -A "$native_root")" ]; then
		printf 'error: refusing to take ownership of nonempty directory %s.\n' "$native_root" >&2
		exit 1
	else
		# Ownership taken now is given back if this run never activates a release.
		amicus_native_root_adopted=1
	fi
	# Never steal a lock: even stale-lock recovery can race with another installer.
	if ! mkdir "$native_root/.install-lock" 2>/dev/null; then
		native_lock_pid=$(cat "$native_root/.install-lock/pid" 2>/dev/null || :)
		printf 'error: installation is locked (pid %s). After confirming no installer is running, remove %s/.install-lock.\n' "$native_lock_pid" "$native_root" >&2
		exit 1
	fi
	amicus_native_lock="$native_root/.install-lock"
	printf '%s\n' "$$" >"$amicus_native_lock/pid"
	printf 'amicus-native-v1\n' >"$native_root/.managed"
	mkdir -p "$native_root/releases" "$native_root/bin"
	for native_link in amicus previous; do
		if [ -e "$native_root/bin/$native_link" ] || [ -L "$native_root/bin/$native_link" ]; then
			[ -L "$native_root/bin/$native_link" ] && amicus_native_valid_target "$(readlink "$native_root/bin/$native_link")" || {
				printf 'error: unrecognized managed command target.\n' >&2; exit 1;
			}
		fi
	done
	amicus_native_sweep_orphan_stages
	amicus_native_stage=$(mktemp -d "$native_root/.install.XXXXXX")
	amicus_native_recovered=0
	amicus_native_recover_activation || exit 1
	if [ "$amicus_native_recovered" = 1 ]; then
		amicus_native_prune_releases
	fi
	if [ "${AMICUS_EXPECTED_CURRENT+x}" = x ] && [ "$(readlink "$native_root/bin/amicus" 2>/dev/null || :)" != "$AMICUS_EXPECTED_CURRENT" ]; then
		printf 'error: the active release changed; retry the update.\n' >&2; exit 1
	fi
}

amicus_native_rollback() {
	amicus_install_traps
	amicus_native_prepare_root
	[ -L "$native_root/bin/previous" ] || { printf 'error: no previous compiled release is available.\n' >&2; exit 1; }
	native_previous=$(readlink "$native_root/bin/previous")
	native_current=$(readlink "$native_root/bin/amicus")
	if [ -n "${AMICUS_EXPECTED_PREVIOUS:-}" ] && [ "$native_previous" != "$AMICUS_EXPECTED_PREVIOUS" ]; then
		printf 'error: the previous release changed while planning rollback; retry.\n' >&2; exit 1
	fi
	[ "$native_previous" != "$native_current" ] || { printf 'error: no different previous release is available.\n' >&2; exit 1; }
	amicus_native_verify_release_target "$native_previous" previous || exit 1
	if amicus_native_verify_release_target "$native_current" current >/dev/null 2>&1; then
		amicus_native_activate "$native_previous" "$native_current"
	else
		# Repair only the active link; keep the healthy rollback target instead of retaining damage.
		amicus_native_atomic_link "$native_previous" "$native_root/bin/amicus" || exit 1
	fi
	amicus_native_prune_releases
	printf 'Restored the previous compiled release.\n'
	amicus_native_cleanup
}

amicus_native_valid_target() {
	amicus_native_parse_target "$1"
	return $?
}

amicus_native_parse_target() {
	native_parsed_target="$1"
	case "$native_parsed_target" in ../releases/*/amicus) ;; *) return 1 ;; esac
	native_parsed_name=${native_parsed_target#../releases/}
	native_parsed_name=${native_parsed_name%/amicus}
	case "$native_parsed_name" in ''|.|..|*/*|*[!0-9A-Za-z.-]*) return 1 ;; esac
	native_parsed_digest_suffix=${native_parsed_name##*-}
	native_parsed_digest=${native_parsed_digest_suffix%%.*}
	[ "${#native_parsed_digest}" -eq 64 ] || return 1
	case "$native_parsed_digest" in *[!0-9a-f]*) return 1 ;; esac
	if [ "$native_parsed_digest_suffix" != "$native_parsed_digest" ]; then
		native_parsed_unique=${native_parsed_digest_suffix#"$native_parsed_digest".}
		[ "${#native_parsed_unique}" -eq 6 ] || return 1
		case "$native_parsed_unique" in *[!0-9A-Za-z]*) return 1 ;; esac
	fi
	native_parsed_prefix=${native_parsed_name%-"$native_parsed_digest_suffix"}
	# Longest platform suffix first: a shorter arm matches the prefix of a longer
	# platform name, so `<version>-linux-x64-musl` must not be read as `linux-x64`.
	case "$native_parsed_prefix" in
		*-linux-x64-musl-baseline) native_parsed_platform=linux-x64-musl-baseline ;;
		*-linux-x64-musl) native_parsed_platform=linux-x64-musl ;;
		*-linux-x64-baseline) native_parsed_platform=linux-x64-baseline ;;
		*-linux-arm64-musl) native_parsed_platform=linux-arm64-musl ;;
		*-darwin-arm64) native_parsed_platform=darwin-arm64 ;;
		*-darwin-x64) native_parsed_platform=darwin-x64 ;;
		*-linux-arm64) native_parsed_platform=linux-arm64 ;;
		*-linux-x64) native_parsed_platform=linux-x64 ;;
		*) return 1 ;;
	esac
	native_parsed_version=${native_parsed_prefix%-"$native_parsed_platform"}
	printf '%s\n' "$native_parsed_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || return 1
	native_parsed_dir="$native_root/releases/$native_parsed_name"
}

amicus_native_validate_asset() {
	native_asset_release_dir="$1"
	native_asset_relative="$2"
	native_asset_path="$native_asset_release_dir/$native_asset_relative"
	[ -f "$native_asset_path" ] && [ ! -L "$native_asset_path" ] || return 1
	case "$native_asset_relative" in
		*/*) native_asset_parent_relative=${native_asset_relative%/*} ;;
		*) native_asset_parent_relative= ;;
	esac
	if [ -n "$native_asset_parent_relative" ]; then
		native_asset_expected_parent="$native_asset_release_dir/$native_asset_parent_relative"
	else
		native_asset_expected_parent="$native_asset_release_dir"
	fi
	native_asset_actual_parent=$(CDPATH= cd "$(dirname "$native_asset_path")" 2>/dev/null && pwd -P) || return 1
	[ "$native_asset_actual_parent" = "$native_asset_expected_parent" ]
}

amicus_native_validate_release_metadata() {
	native_metadata_target="$1"
	amicus_native_parse_target "$native_metadata_target" || return 1
	native_metadata_dir="$native_parsed_dir"
	native_metadata_version="$native_parsed_version"
	native_metadata_digest="$native_parsed_digest"
	[ -d "$native_metadata_dir" ] && [ ! -L "$native_metadata_dir" ] || return 1
	[ "$(CDPATH= cd "$native_metadata_dir" 2>/dev/null && pwd -P)" = "$native_metadata_dir" ] || return 1
	for native_metadata_asset in amicus package.json install.sh amicus-runtime/pyproject.toml amicus-runtime/src/rlm/repl.py theme/prime.json export-html/template.html photon_rs_bg.wasm .archive-sha256 .install-source; do
		amicus_native_validate_asset "$native_metadata_dir" "$native_metadata_asset" || return 1
	done
	[ "$(cat "$native_metadata_dir/.archive-sha256")" = "$native_metadata_digest" ] || return 1
	native_metadata_package_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$native_metadata_dir/package.json")
	[ "$native_metadata_package_version" = "$native_metadata_version" ] || return 1
	native_metadata_source=$(cat "$native_metadata_dir/.install-source")
	case "$native_metadata_source" in http://*|https://*) ;; *) return 1 ;; esac
}

amicus_native_probe_timeout() {
	# The first run of a freshly extracted executable can be slow: Rosetta 2 translates
	# the whole binary before it prints anything, and a cold page cache adds more. A
	# 51 MB x64 executable measured 11.3s cold and 0.2s warm on Apple Silicon.
	native_probe_timeout=60
	case "${AMICUS_PROBE_TIMEOUT_SECONDS:-}" in
		''|*[!0-9]*) ;;
		*)
			# $((...)) reads leading-zero constants as octal: "010" would become an
			# 8-second deadline while being reported as 10, and "08"/"09" are invalid
			# octal and abort the arithmetic under set -eu. Strip the leading zeroes
			# so the accepted value stays decimal; an all-zero value strips to the
			# empty string and falls back to the default like any invalid value.
			native_probe_timeout="${AMICUS_PROBE_TIMEOUT_SECONDS#"${AMICUS_PROBE_TIMEOUT_SECONDS%%[!0]*}"}"
			[ -n "$native_probe_timeout" ] && [ "$native_probe_timeout" -le 600 ] || native_probe_timeout=60
			;;
	esac
	printf '%s\n' "$native_probe_timeout"
}

amicus_native_probe() (
	# macOS does not ship timeout; keep the deadline independent of Node and Python.
	native_probe_pid=
	trap '
		if [ -n "$native_probe_pid" ]; then
			kill -KILL "$native_probe_pid" 2>/dev/null || :
			wait "$native_probe_pid" 2>/dev/null || :
		fi
	' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	trap 'exit 129' HUP
	"$@" &
	native_probe_pid=$!
	native_probe_timeout=$(amicus_native_probe_timeout)
	# date +%s truncates to whole seconds, so add one to avoid killing a probe early.
	native_probe_deadline=$(($(date +%s) + native_probe_timeout + 1))
	while kill -0 "$native_probe_pid" 2>/dev/null; do
		if [ "$(date +%s)" -ge "$native_probe_deadline" ]; then
			printf 'error: executable probe timed out after %s seconds.\n' "$native_probe_timeout" >&2
			kill -KILL "$native_probe_pid" 2>/dev/null || :
			wait "$native_probe_pid" 2>/dev/null || :
			native_probe_pid=
			exit 124
		fi
		sleep 0.1
	done
	if wait "$native_probe_pid"; then native_probe_status=0; else native_probe_status=$?; fi
	native_probe_pid=
	exit "$native_probe_status"
)

# Bun's musl executables link against libstdc++, which Alpine does not preinstall.
# The loader either names the library or reports a wall of C++ relocation failures.
amicus_native_probe_missing_libstdcxx() {
	native_probe_log="$1"
	[ -f "$native_probe_log" ] || return 1
	grep -q 'libstdc++\.so\.6' "$native_probe_log" && return 0
	# musl names no library when every C++ runtime symbol is unresolved, so match
	# the mangled and Itanium ABI names it does report.
	grep -Eq 'Error relocating .*: (_Z|__cxa_|__dynamic_cast|__once_proxy)[A-Za-z0-9_]*: symbol not found' "$native_probe_log"
}

# One actionable line beats sixty relocation errors the user cannot act on.
amicus_native_report_missing_libstdcxx() {
	printf 'error: the compiled executable needs the libstdc++ runtime library, which is missing here.\n' >&2
	printf 'Install it and run this installer again (Alpine: apk add --no-cache libstdc++).\n' >&2
	printf 'To install the Node.js build instead, set AMICUS_INSTALL_METHOD=node.\n' >&2
}

amicus_native_verify_release_target() {
	native_verify_target="$1"
	native_verify_label="$2"
	if ! amicus_native_validate_release_metadata "$native_verify_target"; then
		printf 'error: invalid %s release metadata or assets. The active release was kept.\n' "$native_verify_label" >&2
		return 1
	fi
	native_verify_dir="$native_metadata_dir"
	native_verify_version="$native_metadata_version"
	if ! amicus_native_probe "$native_verify_dir/amicus" --version >"$amicus_native_stage/$native_verify_label.version" 2>"$amicus_native_stage/$native_verify_label.probe.log"; then
		cat "$amicus_native_stage/$native_verify_label.probe.log" >&2
		printf 'error: the %s release executable could not be validated. The active release was kept.\n' "$native_verify_label" >&2
		return 1
	fi
	if [ "$(cat "$amicus_native_stage/$native_verify_label.version")" != "$native_verify_version" ]; then
		printf 'error: the %s release executable reports a different version. The active release was kept.\n' "$native_verify_label" >&2
		return 1
	fi
	if ! amicus_native_probe "$native_verify_dir/amicus" --help >"$amicus_native_stage/$native_verify_label.help" 2>"$amicus_native_stage/$native_verify_label.help.log"; then
		cat "$amicus_native_stage/$native_verify_label.help.log" >&2
		printf 'error: the %s release executable failed its help probe. The active release was kept.\n' "$native_verify_label" >&2
		return 1
	fi
}

amicus_native_sweep_orphan_stages() {
	for native_orphan_stage in "$native_root"/.install.*; do
		[ -e "$native_orphan_stage" ] || [ -L "$native_orphan_stage" ] || continue
		native_orphan_name=${native_orphan_stage##*/}
		native_orphan_suffix=${native_orphan_name#.install.}
		[ "${#native_orphan_suffix}" -eq 6 ] || continue
		case "$native_orphan_suffix" in *[!0-9A-Za-z]*) continue ;; esac
		[ -d "$native_orphan_stage" ] && [ ! -L "$native_orphan_stage" ] || continue
		rm -rf "$native_orphan_stage"
	done
}

amicus_native_release_in_use() {
	native_usage_executable="$1"
	if native_lsof=$(command -v lsof 2>/dev/null); then
		:
	elif [ -x /usr/sbin/lsof ]; then
		native_lsof=/usr/sbin/lsof
	elif [ -x /usr/bin/lsof ]; then
		native_lsof=/usr/bin/lsof
	else
		return 2
	fi
	if "$native_lsof" -n -F p "$native_usage_executable" >"$amicus_native_stage/lsof.out" 2>"$amicus_native_stage/lsof.err"; then
		return 0
	else
		native_lsof_status=$?
	fi
	[ "$native_lsof_status" -eq 1 ] && [ ! -s "$amicus_native_stage/lsof.err" ] && return 1
	return 2
}

amicus_native_prune_releases() {
	native_prune_current=$(readlink "$native_root/bin/amicus" 2>/dev/null || :)
	native_prune_previous=$(readlink "$native_root/bin/previous" 2>/dev/null || :)
	for native_prune_dir in "$native_root"/releases/*; do
		[ -e "$native_prune_dir" ] || [ -L "$native_prune_dir" ] || continue
		[ -d "$native_prune_dir" ] && [ ! -L "$native_prune_dir" ] || continue
		native_prune_target="../releases/${native_prune_dir##*/}/amicus"
		[ "$native_prune_target" != "$native_prune_current" ] || continue
		[ "$native_prune_target" != "$native_prune_previous" ] || continue
		amicus_native_validate_release_metadata "$native_prune_target" || continue
		if amicus_native_release_in_use "$native_prune_dir/amicus"; then
			continue
		else
			native_prune_usage_status=$?
		fi
		[ "$native_prune_usage_status" -eq 1 ] || continue
		rm -rf "$native_prune_dir"
	done
}

amicus_native_recover_activation() {
	native_activation_state="$native_root/.activation-state"
	if [ ! -e "$native_activation_state" ] && [ ! -L "$native_activation_state" ]; then
		return 0
	fi
	if [ ! -f "$native_activation_state" ] || [ -L "$native_activation_state" ] ||
		[ "$(wc -l <"$native_activation_state" | tr -d ' ')" != 2 ]; then
		printf 'error: invalid activation recovery state at %s. Restore bin/amicus and bin/previous, then remove it.\n' "$native_activation_state" >&2
		return 1
	fi
	native_recovery_target=$(sed -n '1p' "$native_activation_state")
	native_recovery_previous=$(sed -n '2p' "$native_activation_state")
	amicus_native_verify_release_target "$native_recovery_target" recovery-target || return 1
	if [ -n "$native_recovery_previous" ]; then
		amicus_native_verify_release_target "$native_recovery_previous" recovery-previous || return 1
	fi
	native_recovery_current=$(readlink "$native_root/bin/amicus" 2>/dev/null || :)
	if [ "$native_recovery_current" = "$native_recovery_target" ]; then
		if [ -n "$native_recovery_previous" ] && [ "$native_recovery_previous" != "$native_recovery_target" ] &&
			[ "$(readlink "$native_root/bin/previous" 2>/dev/null || :)" != "$native_recovery_previous" ]; then
			amicus_native_atomic_link "$native_recovery_previous" "$native_root/bin/previous" || return 1
		fi
	elif [ "$native_recovery_current" != "$native_recovery_previous" ]; then
		printf 'error: activation recovery is ambiguous: bin/amicus matches neither recorded release. Restore the links using %s before retrying.\n' "$native_activation_state" >&2
		return 1
	fi
	rm -f "$native_activation_state" || return 1
	amicus_native_recovered=1
}

amicus_native_check_public_link() {
	native_public_bin="${AMICUS_BIN_DIR:-$HOME/.local/bin}"
	case "$native_public_bin" in /*) ;; *) printf 'error: bin directory must be absolute.\n' >&2; exit 1 ;; esac
	if [ "${AMICUS_INSTALL_LINK:-1}" = 0 ]; then return; fi
	case "$amicus_cmd" in
		''|.|..|*/*) printf 'error: command name must be a basename.\n' >&2; exit 1 ;;
	esac
	if [ -e "$native_public_bin/$amicus_cmd" ] || [ -L "$native_public_bin/$amicus_cmd" ]; then
		if [ ! -L "$native_public_bin/$amicus_cmd" ] || [ "$(readlink "$native_public_bin/$amicus_cmd")" != "$native_root/bin/amicus" ]; then
			printf 'error: refusing to replace existing command %s/%s.\n' "$native_public_bin" "$amicus_cmd" >&2
			printf 'Choose AMICUS_BIN_DIR or set AMICUS_INSTALL_LINK=0.\n' >&2
			exit 1
		fi
	fi
	mkdir -p "$native_public_bin"
}

amicus_native_validate_archive() {
	LC_ALL=C tar -tzf "$native_archive" >"$amicus_native_stage/entries"
	awk '
		/^\// || /(^|\/)\.\.(\/|$)/ || /\\/ { bad=1 }
		END { exit bad }
	' "$amicus_native_stage/entries" || { printf 'error: unsafe archive path.\n' >&2; exit 1; }
	LC_ALL=C tar -tvzf "$native_archive" >"$amicus_native_stage/types"
	awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { bad=1 } END { exit bad }' \
		"$amicus_native_stage/types" || { printf 'error: archive contains links or special files.\n' >&2; exit 1; }
}

amicus_native_atomic_link() {
	native_link_stage=$(mktemp -d "$amicus_native_stage/link.XXXXXX") || return 1
	ln -s "$1" "$native_link_stage/link" || return 1
	# The destination is an executable link, never a directory link.
	mv -f "$native_link_stage/link" "$2" || return 1
	rmdir "$native_link_stage" || return 1
}

amicus_native_activate() {
	amicus_native_activation_target="$1"
	amicus_native_activation_previous="$2"
	{
		printf '%s\n' "$1"
		printf '%s\n' "$2"
	} >"$amicus_native_stage/activation-state"
	mv -f "$amicus_native_stage/activation-state" "$native_root/.activation-state"
	amicus_native_atomic_link "$1" "$native_root/bin/amicus"
	if [ -n "$2" ] && [ "$1" != "$2" ]; then
		amicus_native_atomic_link "$2" "$native_root/bin/previous"
	fi
	rm -f "$native_root/.activation-state"
	amicus_native_activation_target=
	amicus_native_activation_previous=
}

amicus_release_is_node_only() {
	awk -v file="$2" '
		$2 ~ /\.tar\.gz$/ { compiled=1 }
		$2 == file { count++; if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-fA-F]/) invalid=1 }
		END { exit compiled || invalid || count != 1 }
	' "$1"
}

amicus_install_native() {
	native_platform="$1"
	shift
	if [ "$amicus_base_url" = "$amicus_unconfigured_base_url" ]; then
		printf 'error: set AMICUS_DOWNLOAD_BASE_URL or use the published installer.\n' >&2; exit 1
	fi
	amicus_validate_download_base_url
	amicus_install_traps
	amicus_init_screen
	native_version=$(resolve_amicus_version "$@")
	printf '%s\n' "$native_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
		printf 'error: invalid native release version.\n' >&2; exit 1;
	}
	# Select the release format before touching native-owned installation paths.
	amicus_download_dir=$(create_temp_dir)
	native_file="amicus-$native_version-$native_platform.tar.gz"
	native_checksums="$amicus_download_dir/SHA256SUMS"
	amicus_run_quiet_with_animation "Downloading Amicus" "Downloading release checksums" "Amicus v$native_version" \
		amicus_curl_download -fsSL --connect-timeout 10 --max-time 120 "$amicus_base_url/releases/v$native_version/SHA256SUMS" -o "$native_checksums"
	awk -v file="$native_file" '$2 == file { count++; hash=$1; fields=NF } END { if (count != 1 || fields != 2 || length(hash) != 64 || hash ~ /[^0-9a-fA-F]/) exit 1; print tolower(hash) "  " file }' \
		"$native_checksums" >"$amicus_download_dir/selected.sha256" || {
		if [ "${AMICUS_INSTALL_METHOD:-auto}" = auto ] &&
			amicus_release_is_node_only "$native_checksums" "$amicus_package-$native_version.tgz"; then
			rm -rf "$amicus_download_dir"
			amicus_download_dir=
			printf 'This release only provides npm packages; using the Node installation.\n' >&2
			amicus_install_node "$native_version"
			return
		fi
		printf 'error: expected one valid checksum for %s.\n' "$native_file" >&2; exit 1;
	}
	if [ "${AMICUS_INSTALLER_NONINTERACTIVE:-0}" != 1 ]; then
		if amicus_prompt_yes_no "Install Amicus v$native_version?" "Downloads and verifies the compiled application." "Install? [Y/n]"; then
			:
		else
			native_prompt_status=$?
			[ "$native_prompt_status" = 2 ] || return 0
		fi
	fi
	amicus_native_prepare_root
	mv "$amicus_download_dir/selected.sha256" "$amicus_native_stage/selected.sha256"
	rm -rf "$amicus_download_dir"
	amicus_download_dir=
	native_archive="$amicus_native_stage/$native_file"
	if [ -n "${AMICUS_EXPECTED_SHA256:-}" ] && [ "$(awk '{print $1}' "$amicus_native_stage/selected.sha256")" != "$AMICUS_EXPECTED_SHA256" ]; then
		printf 'error: release manifest and checksum inventory disagree.\n' >&2; exit 1
	fi
	amicus_run_quiet_with_animation "Downloading Amicus" "Downloading compiled Amicus" "$native_platform" \
		amicus_curl_download -fsSL --connect-timeout 10 --max-time 300 "$amicus_base_url/releases/v$native_version/$native_file" -o "$native_archive"
	if command -v sha256sum >/dev/null 2>&1; then native_checker=sha256sum; else native_checker=shasum; fi
	amicus_run_quiet_with_animation "Verifying Amicus" "Verifying SHA-256" "Checking the downloaded archive." \
		amicus_run_checksum_check "$amicus_native_stage" selected.sha256 "$native_checker"
	amicus_native_validate_archive
	mkdir "$amicus_native_stage/application"
	tar -xzf "$native_archive" -C "$amicus_native_stage/application"
	native_extracted="$amicus_native_stage/application"
	for native_asset in amicus package.json install.sh amicus-runtime/pyproject.toml amicus-runtime/src/rlm/repl.py theme/prime.json export-html/template.html photon_rs_bg.wasm; do
		[ -f "$native_extracted/$native_asset" ] || { printf 'error: missing archive asset: %s\n' "$native_asset" >&2; exit 1; }
	done
	native_probe_status=0
	amicus_native_probe "$native_extracted/amicus" --version >"$amicus_native_stage/version" 2>"$amicus_native_stage/probe.log" ||
		native_probe_status=$?
	if [ "$native_probe_status" -ne 0 ]; then
		# A missing libstdc++ is one package away, so name it instead of downloading Node.
		if amicus_native_probe_missing_libstdcxx "$amicus_native_stage/probe.log"; then
			amicus_native_cleanup
			amicus_native_report_missing_libstdcxx
			exit 1
		fi
		cat "$amicus_native_stage/probe.log" >&2
		amicus_native_cleanup
		# A timeout means the executable never answered, not that it cannot run here.
		if [ "$native_probe_status" -eq 124 ]; then
			native_probe_hint="Set AMICUS_PROBE_TIMEOUT_SECONDS to a larger value and run the installer again."
			if [ "${AMICUS_INSTALL_METHOD:-auto}" = auto ]; then
				printf 'The compiled executable did not answer in time; using the Node installation. %s\n' "$native_probe_hint" >&2
				amicus_install_node "$native_version"
				return
			fi
			printf 'error: the compiled executable did not answer within %s seconds. %s\n' \
				"$(amicus_native_probe_timeout)" "$native_probe_hint" >&2
			exit 1
		fi
		if [ "${AMICUS_INSTALL_METHOD:-auto}" = auto ]; then
			printf 'The compiled executable cannot run here; using the Node installation.\n' >&2
			amicus_install_node "$native_version"
			return
		fi
		printf 'error: the compiled executable cannot run on this machine.\n' >&2; exit 1
	fi
	[ "$(cat "$amicus_native_stage/version")" = "$native_version" ] || { printf 'error: archive version mismatch.\n' >&2; exit 1; }
	amicus_native_probe "$native_extracted/amicus" --help >"$amicus_native_stage/help"
	amicus_native_check_public_link
	native_digest=$(awk '{ print $1 }' "$amicus_native_stage/selected.sha256")
	native_release_name="$native_version-$native_platform-$native_digest"
	native_destination="$native_root/releases/$native_release_name"
	if [ -e "$native_destination" ] || [ -L "$native_destination" ]; then
		# Reinstalls activate fresh assets without modifying a running release.
		native_destination=$(mktemp -d "$native_destination.XXXXXX")
		rmdir "$native_destination"
		native_release_name=${native_destination##*/}
	fi
	printf '%s\n' "$native_digest" >"$native_extracted/.archive-sha256"
	printf '%s\n' "$amicus_base_url" >"$native_extracted/.install-source"
	mv "$native_extracted" "$native_destination"
	if [ "${AMICUS_BOOTSTRAP_KERNEL_ON_INSTALL:-}" != 0 ]; then
		confirm_kernel_runtime_setup
		if [ "$amicus_bootstrap_kernel_on_install" = 1 ]; then
			if ! amicus_run_quiet_with_animation "Preparing Python" "Preparing Python runtime" "Installing uv and Python dependencies." \
				env AMICUS_INSTALL_UV=1 "$native_destination/amicus" --amicus-bootstrap; then
				printf 'Python preparation failed; retry on first Python use.\n' >&2
			fi
		fi
	fi
	amicus_native_check_public_link
	native_target="../releases/$native_release_name/amicus"
	native_previous=
	if [ -L "$native_root/bin/amicus" ]; then
		native_previous=$(readlink "$native_root/bin/amicus")
	fi
	# A fresh public command must point to an already activated executable.
	if [ -z "$native_previous" ]; then
		amicus_native_activate "$native_target" ""
	fi
	if [ "${AMICUS_INSTALL_LINK:-1}" != 0 ] && [ ! -L "$native_public_bin/$amicus_cmd" ]; then
		ln -sn "$native_root/bin/amicus" "$native_public_bin/$amicus_cmd"
	fi
	# Keep an existing release active if creating the public command loses a race.
	if [ -n "$native_previous" ]; then
		if amicus_native_verify_release_target "$native_previous" current >/dev/null 2>&1; then
			amicus_native_activate "$native_target" "$native_previous"
		else
			amicus_native_atomic_link "$native_target" "$native_root/bin/amicus" || exit 1
		fi
	fi
	amicus_native_prune_releases
	if [ "${AMICUS_INSTALL_LINK:-1}" != 0 ]; then
		amicus_native_configure_path || printf 'Add %s to PATH to run Amicus.\n' "$native_public_bin" >&2
	fi
	amicus_screen "Amicus installed" "" "Run it with: $amicus_cmd" ""
	printf 'Installed Amicus %s at %s\n' "$native_version" "$native_root/bin/amicus"
	amicus_native_cleanup
}

amicus_native_configure_path() {
	case ":$amicus_original_path:" in *":$native_public_bin:"*) return ;; esac
	native_path_line="export PATH=$(amicus_shell_quote "$native_public_bin"):\$PATH"
	if native_profile=$(detect_shell_profile); then
		if ! grep -Fx "$native_path_line" "$native_profile" >/dev/null 2>&1; then
			mkdir -p "$(dirname "$native_profile")"
			printf '\n# Amicus\n%s\n' "$native_path_line" >>"$native_profile"
		fi
	fi
	printf 'For this shell, run: %s\n' "$native_path_line"
}

main "$@"
