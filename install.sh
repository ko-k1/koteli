#!/bin/sh

set -eu

program_name="Koteli"
repository="${KOTELI_REPOSITORY:-ko-k1/koteli}"
ref="${KOTELI_REF:-main}"
binaries="koteli kxaid"

temp_dir=""
saved_tty_state=""
cleanup_done=0
active_stage=""
active_detail=""

cleanup() {
	cleanup_status="$1"
	if [ "$cleanup_done" -ne 0 ]; then
		exit "$cleanup_status"
	fi
	cleanup_done=1
	trap - 0 HUP INT TERM

	if [ -n "$saved_tty_state" ] && [ -r /dev/tty ]; then
		stty "$saved_tty_state" < /dev/tty >/dev/null 2>&1 || :
		saved_tty_state=""
	fi
	if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
		rm -rf "$temp_dir" >/dev/null 2>&1 || :
		temp_dir=""
	fi
	exit "$cleanup_status"
}

trap 'cleanup "$?"' 0
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

ui_rich=0
ui_unicode=0
ui_reset=""
ui_bold=""
ui_cyan=""
ui_purple=""
ui_green=""
ui_amber=""
ui_red=""
ui_muted=""
ui_erase=""
ui_brand_mark="*"
ui_active_mark=">"
ui_ok_mark="+"
ui_separator="-"
ui_arrow="->"

init_ui() {
	if [ -t 1 ] && [ -t 2 ] &&
		[ -z "${CI:-}" ] &&
		[ "${TERM:-}" != "dumb" ] &&
		[ "${NO_COLOR+x}" != "x" ]; then
		ui_rich=1
		ui_reset=$(printf '\033[0m')
		ui_bold=$(printf '\033[1m')
		ui_cyan=$(printf '\033[36m')
		ui_purple=$(printf '\033[35m')
		ui_green=$(printf '\033[32m')
		ui_amber=$(printf '\033[33m')
		ui_red=$(printf '\033[31m')
		ui_muted=$(printf '\033[90m')
		ui_erase=$(printf '\033[2K')

		ui_locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
		case "$ui_locale" in
			*UTF-8* | *utf-8* | *UTF8* | *utf8*)
				ui_unicode=1
				ui_brand_mark=$(printf '\342\227\206')
				ui_active_mark=$(printf '\342\227\207')
				ui_ok_mark=$(printf '\342\234\223')
				ui_separator=$(printf '\302\267')
				ui_arrow=$(printf '\342\206\222')
				;;
		esac
	fi
}

ui_header() {
	if [ "$ui_rich" -eq 1 ]; then
		printf '%s%s%s %s%sKoteli%s\n' \
			"$ui_cyan" "$ui_brand_mark" "$ui_reset" \
			"$ui_bold" "$ui_purple" "$ui_reset"
	else
		printf '%s\n' "== Koteli =="
	fi
}

ui_detail() {
	ui_detail_label="$1"
	ui_detail_value="$2"
	if [ "$ui_rich" -eq 1 ]; then
		printf '%s%s:%s %s\n' "$ui_muted" "$ui_detail_label" "$ui_reset" "$ui_detail_value"
	else
		printf '[info] %s: %s\n' "$ui_detail_label" "$ui_detail_value"
	fi
}

stage_start() {
	active_stage="$1"
	active_detail="$2"
	if [ "$ui_rich" -eq 1 ]; then
		printf '%s%s%s %s %s %s' \
			"$ui_cyan" "$ui_active_mark" "$ui_reset" \
			"$active_stage" "$ui_separator" "$active_detail"
	else
		printf '[start] %s - %s\n' "$active_stage" "$active_detail"
	fi
}

stage_ok() {
	stage_result="$1"
	if [ "$ui_rich" -eq 1 ]; then
		printf '\r%s%s%s%s %s %s %s\n' \
			"$ui_erase" "$ui_green" "$ui_ok_mark" "$ui_reset" \
			"$active_stage" "$ui_separator" "$stage_result"
	else
		printf '[ok] %s - %s\n' "$active_stage" "$stage_result"
	fi
	active_stage=""
	active_detail=""
}

stage_error() {
	stage_message="$1"
	if [ "$ui_rich" -eq 1 ]; then
		printf '\r%s%sx%s %s %s %s\n' \
			"$ui_erase" "$ui_red" "$ui_reset" \
			"$active_stage" "$ui_separator" "$stage_message" >&2
	else
		printf '[error] %s - %s\n' "$active_stage" "$stage_message" >&2
	fi
	active_stage=""
	active_detail=""
}

ui_status() {
	status_kind="$1"
	status_label="$2"
	status_detail="$3"
	if [ "$ui_rich" -eq 1 ]; then
		case "$status_kind" in
			ok)
				status_color="$ui_green"
				status_mark="$ui_ok_mark"
				;;
			warn)
				status_color="$ui_amber"
				status_mark="!"
				;;
			error)
				status_color="$ui_red"
				status_mark="x"
				;;
			*)
				status_color="$ui_muted"
				status_mark="-"
				;;
		esac
		printf '%s%s%s %s %s %s\n' \
			"$status_color" "$status_mark" "$ui_reset" \
			"$status_label" "$ui_separator" "$status_detail"
	else
		case "$status_kind" in
			ok) status_token="ok" ;;
			warn) status_token="warn" ;;
			error) status_token="error" ;;
			*) status_token="info" ;;
		esac
		printf '[%s] %s - %s\n' "$status_token" "$status_label" "$status_detail"
	fi
}

ui_warning() {
	ui_status warn "$1" "$2"
}

ui_error() {
	error_message="$1"
	if [ "$ui_rich" -eq 1 ]; then
		printf '%sx%s %s\n' "$ui_red" "$ui_reset" "$error_message" >&2
	else
		printf '[error] %s\n' "$error_message" >&2
	fi
}

ui_receipt() {
	receipt_label="$1"
	receipt_value="$2"
	if [ "$ui_rich" -eq 1 ]; then
		printf '%s%s%s %s: %s\n' \
			"$ui_green" "$ui_ok_mark" "$ui_reset" "$receipt_label" "$receipt_value"
	else
		printf '[result] %s: %s\n' "$receipt_label" "$receipt_value"
	fi
}

ui_next() {
	next_label="$1"
	next_value="$2"
	if [ "$ui_rich" -eq 1 ]; then
		printf '%s>%s %s: %s\n' "$ui_cyan" "$ui_reset" "$next_label" "$next_value"
	else
		printf '[next] %s: %s\n' "$next_label" "$next_value"
	fi
}

fail() {
	fail_message="$*"
	if [ -n "$active_stage" ]; then
		stage_error "$fail_message"
	else
		ui_error "$fail_message"
	fi
	exit 1
}

save_tty_state() {
	[ -r /dev/tty ] && [ -w /dev/tty ] || return 1
	command -v stty >/dev/null 2>&1 || return 1
	tty_snapshot=$(stty -g < /dev/tty 2>/dev/null) || return 1
	[ -n "$tty_snapshot" ] || return 1
	saved_tty_state="$tty_snapshot"
	return 0
}

restore_tty() {
	if [ -n "$saved_tty_state" ]; then
		stty "$saved_tty_state" < /dev/tty >/dev/null 2>&1 || :
		saved_tty_state=""
	fi
}

action_name() {
	case "$1" in
		update) printf '%s' "Update" ;;
		repair) printf '%s' "Repair" ;;
		uninstall) printf '%s' "Uninstall" ;;
		*) printf '%s' "Cancel" ;;
	esac
}

print_menu_row() {
	menu_row="$1"
	menu_selected="$2"
	case "$menu_row" in
		0)
			menu_title="Update"
			menu_description="refresh both binaries"
			;;
		1)
			menu_title="Repair"
			menu_description="reinstall both binaries"
			;;
		2)
			menu_title="Uninstall"
			menu_description="remove binaries; state separate"
			;;
		*)
			menu_title="Cancel"
			menu_description="make no changes"
			;;
	esac

	if [ "$menu_row" -eq "$menu_selected" ]; then
		printf '%s%s> [ %-9s ]%s %s\n' \
			"$ui_bold" "$ui_cyan" "$menu_title" "$ui_reset" "$menu_description"
	else
		printf '  [ %-9s ] %s\n' "$menu_title" "$menu_description"
	fi
}

render_button_menu() {
	render_selected="$1"
	render_redraw="$2"
	if [ "$render_redraw" -eq 1 ]; then
		printf '%s' "$menu_cursor_up"
	fi
	render_row=0
	while [ "$render_row" -lt 4 ]; do
		if [ "$render_redraw" -eq 1 ]; then
			printf '%s' "$menu_erase_line"
		fi
		print_menu_row "$render_row" "$render_selected"
		render_row=$((render_row + 1))
	done
}

numbered_menu() {
	if [ -z "$saved_tty_state" ] && ! save_tty_state; then
		fail "Koteli is already installed. Set KOTELI_ACTION to update, repair, uninstall, or cancel."
	fi

	while :; do
		printf '%s\n' \
			"  1) Update    - refresh both binaries" \
			"  2) Repair    - reinstall both binaries" \
			"  3) Uninstall - remove binaries; configuration is handled separately" \
			"  4) Cancel    - make no changes"
		printf 'Choose an action [1-4] (default 4): ' > /dev/tty
		if ! IFS= read -r menu_choice < /dev/tty; then
			restore_tty
			fail "could not read a menu choice; set KOTELI_ACTION to update, repair, uninstall, or cancel"
		fi
		case "$menu_choice" in
			1 | update | UPDATE)
				action="update"
				break
				;;
			2 | repair | REPAIR)
				action="repair"
				break
				;;
			3 | uninstall | UNINSTALL)
				action="uninstall"
				break
				;;
			4 | cancel | CANCEL | '')
				action="cancel"
				break
				;;
			*)
				ui_warning "Menu" "invalid choice: $menu_choice"
				;;
		esac
	done
	restore_tty
	printf 'Selected: %s\n' "$(action_name "$action")"
}

button_menu() {
	button_default="$1"
	if ! save_tty_state; then
		numbered_menu
		return
	fi

	if ! command -v tput >/dev/null 2>&1; then
		numbered_menu
		return
	fi
	menu_width=$(tput cols 2>/dev/null) || {
		numbered_menu
		return
	}
	case "$menu_width" in
		'' | *[!0-9]*)
			numbered_menu
			return
			;;
	esac
	if [ "$menu_width" -lt 48 ]; then
		numbered_menu
		return
	fi
	menu_cursor_up=$(tput cuu 4 2>/dev/null) || {
		numbered_menu
		return
	}
	menu_erase_line=$(tput el 2>/dev/null) || {
		numbered_menu
		return
	}
	if [ -z "$menu_cursor_up" ]; then
		numbered_menu
		return
	fi

	if ! stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null; then
		restore_tty
		numbered_menu
		return
	fi

	menu_selected="$button_default"
	printf '%sUse Up/Down, Enter, Esc, or 1-4.%s\n' "$ui_muted" "$ui_reset"
	render_button_menu "$menu_selected" 0

	while :; do
		if ! menu_key=$(dd bs=1 count=1 < /dev/tty 2>/dev/null); then
			restore_tty
			numbered_menu
			return
		fi
		case "$menu_key" in
			'')
				break
				;;
			1)
				menu_selected=0
				render_button_menu "$menu_selected" 1
				break
				;;
			2)
				menu_selected=1
				render_button_menu "$menu_selected" 1
				break
				;;
			3)
				menu_selected=2
				render_button_menu "$menu_selected" 1
				break
				;;
			4)
				menu_selected=3
				render_button_menu "$menu_selected" 1
				break
				;;
			"$(printf '\033')")
				if ! stty -echo -icanon min 0 time 1 < /dev/tty 2>/dev/null; then
					restore_tty
					numbered_menu
					return
				fi
				if ! menu_key_2=$(dd bs=1 count=1 < /dev/tty 2>/dev/null); then
					restore_tty
					numbered_menu
					return
				fi
				if [ "$menu_key_2" = "[" ]; then
					if ! menu_key_3=$(dd bs=1 count=1 < /dev/tty 2>/dev/null); then
						restore_tty
						numbered_menu
						return
					fi
				else
					menu_key_3=""
				fi
				if ! stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null; then
					restore_tty
					numbered_menu
					return
				fi
				case "$menu_key_2:$menu_key_3" in
					'[:A')
						menu_selected=$(((menu_selected + 3) % 4))
						render_button_menu "$menu_selected" 1
						;;
					'[:B')
						menu_selected=$(((menu_selected + 1) % 4))
						render_button_menu "$menu_selected" 1
						;;
					*)
						menu_selected=3
						render_button_menu "$menu_selected" 1
						break
						;;
				esac
				;;
		esac
	done

	case "$menu_selected" in
		0) action="update" ;;
		1) action="repair" ;;
		2) action="uninstall" ;;
		*) action="cancel" ;;
	esac
	restore_tty
	printf 'Selected: %s\n' "$(action_name "$action")"
}

choose_existing_action() {
	if [ -n "${KOTELI_ACTION:-}" ]; then
		case "$KOTELI_ACTION" in
			update | UPDATE) action="update" ;;
			repair | REPAIR | install | INSTALL) action="repair" ;;
			uninstall | UNINSTALL) action="uninstall" ;;
			cancel | CANCEL) action="cancel" ;;
			*)
				fail "invalid KOTELI_ACTION '$KOTELI_ACTION'; use update, repair, uninstall, or cancel"
				;;
		esac
		return
	fi

	if [ "$ui_rich" -eq 1 ]; then
		if [ "$installed_files" -eq 2 ]; then
			button_menu 0
		else
			button_menu 1
		fi
	else
		numbered_menu
	fi
}

resolve_config_removal() {
	remove_config="no"
	if [ -n "${KOTELI_REMOVE_CONFIG:-}" ]; then
		case "$KOTELI_REMOVE_CONFIG" in
			1 | true | TRUE | y | Y | yes | YES)
				remove_config="yes"
				;;
			0 | false | FALSE | n | N | no | NO)
				;;
			*)
				fail "invalid KOTELI_REMOVE_CONFIG '$KOTELI_REMOVE_CONFIG'; use yes or no"
				;;
		esac
		return
	fi

	if [ -n "${KOTELI_ACTION:-}" ]; then
		return
	fi

	ui_warning "Koteli state" "$config_dir (legacy kxai compatibility path)"
	ui_detail "Local projects" ".kxai and .koteli remain untouched"
	if save_tty_state; then
		printf 'Remove Koteli user configuration and state? [y/N] ' > /dev/tty
		if IFS= read -r config_choice < /dev/tty; then
			case "$config_choice" in
				y | Y | yes | YES) remove_config="yes" ;;
			esac
		fi
		restore_tty
	fi
}

uninstall_koteli() {
	resolve_config_removal

	config_exists=0
	if [ -e "$config_dir" ] || [ -L "$config_dir" ]; then
		config_exists=1
	fi
	if [ "$remove_config" = "yes" ] && [ "$config_exists" -eq 1 ]; then
		case "$config_dir" in
			*/kxai/tui/.kxai | */kxai-tui/.kxai)
				;;
			*)
				fail "refusing to remove unexpected configuration path: $config_dir"
				;;
		esac
	fi

	ui_status ok "Fetch" "not required for uninstall"
	ui_status ok "Validate format" "not required for uninstall"

	koteli_remove_status="not found"
	kxaid_remove_status="not found"
	stage_start "Install/Remove" "remove binaries and state"
	for managed_name in $binaries; do
		managed_path="${install_dir}/${managed_name}"
		if [ -f "$managed_path" ] || [ -L "$managed_path" ]; then
			if ! rm -f "$managed_path" 2>/dev/null; then
				fail "$managed_name: could not remove $managed_path"
			fi
			case "$managed_name" in
				koteli) koteli_remove_status="removed" ;;
				kxaid) kxaid_remove_status="removed" ;;
			esac
		fi
	done

	if [ "$remove_config" = "yes" ]; then
		if [ "$config_exists" -eq 1 ]; then
			if ! rm -rf "$config_dir" 2>/dev/null; then
				fail "Koteli state: could not remove $config_dir"
			fi
			config_remove_status="removed"
		else
			config_remove_status="not found"
		fi
	elif [ "$config_exists" -eq 1 ]; then
		config_remove_status="preserved"
	else
		config_remove_status="not found"
	fi
	stage_ok "managed files handled"

	stage_start "PATH" "inspect current shell"
	path_remove_status="unchanged"
	stage_ok "$path_remove_status"

	printf '\n'
	ui_receipt "Action" "uninstalled"
	ui_receipt "koteli" "$koteli_remove_status"
	ui_receipt "kxaid" "$kxaid_remove_status"
	ui_receipt "Destination" "$install_dir"
	ui_receipt "PATH" "$path_remove_status"
	ui_receipt "Koteli state" "$config_remove_status ($config_dir)"
	ui_receipt "Local projects" ".kxai and .koteli preserved"
}

download_file() {
	download_url="$1"
	download_destination="$2"
	case "$download_tool" in
		curl)
			curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 \
				--output "$download_destination" "$download_url" 2>"$download_error_log"
			;;
		wget)
			wget --quiet --tries=3 --timeout=15 \
				--output-document="$download_destination" "$download_url" \
				2>"$download_error_log"
			;;
	esac
}

validate_binary() {
	binary_path="$1"
	binary_name="$2"

	[ -s "$binary_path" ] ||
		fail "$binary_name: empty download for ${platform}/${architecture}"

	magic=$(od -An -tx1 -N4 "$binary_path" 2>/dev/null | tr -d ' \n')
	case "$platform:$magic" in
		linux:7f454c46)
			;;
		macos:cffaedfe | macos:feedfacf | macos:cafebabe | macos:bebafeca | macos:cafebabf | macos:bfbafeca)
			;;
		*)
			fail "$binary_name: invalid ${platform} executable format"
			;;
	esac
}

init_ui
ui_header
stage_start "Detect" "platform, target, and binaries"

command -v uname >/dev/null 2>&1 || fail "uname is required"

detected_system=$(uname -s)
case "$detected_system" in
	Linux) platform="linux" ;;
	Darwin) platform="macos" ;;
	*)
		fail "unsupported operating system: $detected_system; use install.ps1 on Windows"
		;;
esac

detected_machine=$(uname -m)
if [ "$platform" = "macos" ] &&
	[ "$detected_machine" = "x86_64" ] &&
	command -v sysctl >/dev/null 2>&1 &&
	[ "$(sysctl -in sysctl.proc_translated 2>/dev/null || :)" = "1" ]; then
	# Prefer the native Apple Silicon build when the installer runs under Rosetta.
	detected_machine="arm64"
fi
case "$detected_machine" in
	x86_64 | amd64)
		artifact_architecture="amd64"
		if [ "$platform" = "macos" ]; then
			architecture="x64"
		else
			architecture="amd64"
		fi
		;;
	aarch64 | arm64)
		artifact_architecture="aarch64"
		if [ "$platform" = "macos" ]; then
			architecture="arm64"
		else
			architecture="aarch64"
		fi
		;;
	*) fail "unsupported CPU architecture: $detected_machine" ;;
esac

if [ -n "${KOTELI_INSTALL_DIR:-}" ]; then
	install_dir="$KOTELI_INSTALL_DIR"
elif [ -n "${XDG_BIN_HOME:-}" ]; then
	install_dir="$XDG_BIN_HOME"
elif [ -n "${HOME:-}" ]; then
	install_dir="${HOME%/}/.local/bin"
else
	fail "HOME is not set; set KOTELI_INSTALL_DIR to a writable bin directory"
fi

if [ -n "${XDG_STATE_HOME:-}" ]; then
	config_dir="${XDG_STATE_HOME%/}/kxai/tui/.kxai"
elif [ -n "${HOME:-}" ]; then
	config_dir="${HOME%/}/.local/state/kxai/tui/.kxai"
else
	config_dir="${TMPDIR:-/tmp}/kxai-tui/.kxai"
fi

if [ -n "${KOTELI_DOWNLOAD_BASE:-}" ]; then
	download_base="${KOTELI_DOWNLOAD_BASE%/}"
else
	download_base="https://raw.githubusercontent.com/${repository}/${ref}"
fi

installed_files=0
for managed_name in $binaries; do
	managed_path="${install_dir}/${managed_name}"
	if [ -f "$managed_path" ] || [ -L "$managed_path" ]; then
		installed_files=$((installed_files + 1))
	fi
done
stage_ok "${platform}/${architecture}; presence ${installed_files}/2"

if [ "$installed_files" -eq 0 ]; then
	action="install"
else
	if [ "$ui_unicode" -eq 1 ]; then
		printf '%smanage %s %s/%s %s %s%s\n' \
			"$ui_muted" "$ui_separator" "$platform" "$architecture" \
			"$ui_arrow" "$install_dir" "$ui_reset"
	else
		printf 'manage - %s/%s -> %s\n' "$platform" "$architecture" "$install_dir"
	fi
	ui_detail "Binaries" "${installed_files}/2 present"
	choose_existing_action
fi

case "$action" in
	uninstall)
		uninstall_koteli
		exit 0
		;;
	cancel)
		printf '\n'
		ui_receipt "Action" "cancelled"
		ui_receipt "Changes" "none"
		exit 0
		;;
esac

if command -v curl >/dev/null 2>&1; then
	download_tool="curl"
elif command -v wget >/dev/null 2>&1; then
	download_tool="wget"
else
	stage_start "Fetch" "select download tool"
	fail "curl or wget is required"
fi

temp_root="${TMPDIR:-/tmp}"
if ! temp_dir=$(mktemp -d "${temp_root%/}/koteli-install.XXXXXX" 2>/dev/null); then
	stage_start "Fetch" "create temporary workspace"
	fail "could not create a temporary directory under $temp_root"
fi

for binary in $binaries; do
	url="${download_base}/${artifact_architecture}/${platform}/${binary}"
	destination="${temp_dir}/${binary}"
	download_error_log="${temp_dir}/${binary}.download.log"
	stage_start "Fetch" "$binary for ${platform}/${architecture}"
	if ! download_file "$url" "$destination"; then
		fail "$binary: could not download $url"
	fi
	stage_ok "$binary"

	stage_start "Validate format" "$binary"
	validate_binary "$destination" "$binary"
	stage_ok "$binary is a ${platform} executable"
done

stage_start "Install/Remove" "${action} koteli and kxaid"
if ! mkdir -p "$install_dir" 2>/dev/null; then
	fail "could not create $install_dir"
fi
for binary in $binaries; do
	if command -v install >/dev/null 2>&1; then
		if ! install -m 0755 "${temp_dir}/${binary}" "${install_dir}/${binary}" 2>/dev/null; then
			fail "$binary: could not install into $install_dir"
		fi
	else
		if ! cp "${temp_dir}/${binary}" "${install_dir}/${binary}" 2>/dev/null; then
			fail "$binary: could not copy into $install_dir"
		fi
		if ! chmod 0755 "${install_dir}/${binary}" 2>/dev/null; then
			fail "$binary: could not set executable permissions"
		fi
	fi
done
stage_ok "koteli and kxaid installed"

stage_start "PATH" "inspect current shell"
case ":${PATH:-}:" in
	*":${install_dir}:"*)
		path_state="already available"
		stage_ok "$path_state"
		;;
	*)
		path_state="unchanged; install directory is not in PATH"
		stage_ok "$path_state"
		;;
esac

case "$action" in
	install) result="installed" ;;
	repair) result="repaired" ;;
	update) result="updated" ;;
esac

printf '\n'
ui_receipt "Action" "$result"
ui_receipt "Binaries" "koteli, kxaid"
ui_receipt "Destination" "$install_dir"
ui_receipt "PATH" "$path_state"
ui_receipt "Koteli state" "preserved ($config_dir)"
if [ "$path_state" != "already available" ]; then
	ui_next "Add to PATH" "export PATH=\"${install_dir}:\$PATH\""
fi
ui_next "Terminal 1" "kxaid - start the daemon"
ui_next "Terminal 2" "koteli - open Koteli"
