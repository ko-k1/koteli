#!/bin/sh

set -eu

program_name="Koteli"
repository="${KOTELI_REPOSITORY:-ko-k1/koteli}"
ref="${KOTELI_REF:-main}"

say() {
	printf '%s\n' "$*"
}

fail() {
	printf '%s: %s\n' "$program_name installer" "$*" >&2
	exit 1
}

command -v uname >/dev/null 2>&1 || fail "uname is required"

case "$(uname -s)" in
	Linux)
		platform="linux"
		;;
	Darwin)
		platform="macos"
		;;
	*)
		fail "unsupported operating system: $(uname -s). Use install.ps1 on Windows."
		;;
esac

case "$(uname -m)" in
	x86_64 | amd64)
		architecture="amd64"
		;;
	aarch64 | arm64)
		architecture="aarch64"
		;;
	*)
		fail "unsupported CPU architecture: $(uname -m)"
		;;
esac

if [ -n "${KOTELI_INSTALL_DIR:-}" ]; then
	install_dir="${KOTELI_INSTALL_DIR}"
elif [ -n "${XDG_BIN_HOME:-}" ]; then
	install_dir="${XDG_BIN_HOME}"
elif [ -n "${HOME:-}" ]; then
	install_dir="${HOME}/.local/bin"
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

binaries="koteli kxaid"

choose_existing_action() {
	if [ -n "${KOTELI_ACTION:-}" ]; then
		case "$KOTELI_ACTION" in
			update | UPDATE)
				action="update"
				;;
			repair | REPAIR | install | INSTALL)
				action="repair"
				;;
			uninstall | UNINSTALL)
				action="uninstall"
				;;
			cancel | CANCEL)
				action="cancel"
				;;
			*)
				fail "invalid KOTELI_ACTION '$KOTELI_ACTION'; use update, repair, uninstall, or cancel"
				;;
		esac
		return
	fi

	[ -r /dev/tty ] && [ -w /dev/tty ] || \
		fail "Koteli is already installed. Set KOTELI_ACTION to update, repair, uninstall, or cancel."

	while :; do
		say ""
		say "Koteli is already installed in ${install_dir}."
		say "  1) Update"
		say "  2) Repair"
		say "  3) Uninstall"
		say "  4) Cancel"
		printf 'Choose an action [1-4]: ' > /dev/tty
		if ! IFS= read -r choice < /dev/tty; then
			fail "could not read a menu choice"
		fi
		case "$choice" in
			1 | update | UPDATE)
				action="update"
				return
				;;
			2 | repair | REPAIR)
				action="repair"
				return
				;;
			3 | uninstall | UNINSTALL)
				action="uninstall"
				return
				;;
			4 | cancel | CANCEL | '')
				action="cancel"
				return
				;;
			*)
				say "Invalid choice: $choice"
				;;
		esac
	done
}

uninstall_koteli() {
	for managed_name in $binaries koteli; do
		managed_path="${install_dir}/${managed_name}"
		if [ -f "$managed_path" ] || [ -L "$managed_path" ]; then
			rm -f "$managed_path"
		fi
	done

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
	elif [ -z "${KOTELI_ACTION:-}" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
		printf "Also remove Koteli user configuration and state at '%s'? [y/N]: " "$config_dir" > /dev/tty
		if IFS= read -r config_choice < /dev/tty; then
			case "$config_choice" in
				y | Y | yes | YES) remove_config="yes" ;;
			esac
		fi
	fi

	if [ "$remove_config" = "yes" ]; then
		if [ -e "$config_dir" ] || [ -L "$config_dir" ]; then
			case "$config_dir" in
				*/kxai/tui/.kxai | */kxai-tui/.kxai)
					rm -rf "$config_dir"
					say "Removed user configuration and state from ${config_dir}."
					;;
				*)
					fail "refusing to remove unexpected configuration path: $config_dir"
					;;
			esac
		else
			say "No Koteli user configuration or state was found."
		fi
	elif [ -e "$config_dir" ] || [ -L "$config_dir" ]; then
		say "Preserved user configuration and state in ${config_dir}."
	fi
	say "Koteli was uninstalled from ${install_dir}."
	say "Project-local .kxai and .koteli directories were preserved."
}

installed_files=0
for managed_name in $binaries koteli; do
	managed_path="${install_dir}/${managed_name}"
	if [ -f "$managed_path" ] || [ -L "$managed_path" ]; then
		installed_files=$((installed_files + 1))
	fi
done

if [ "$installed_files" -eq 0 ]; then
	action="install"
else
	if [ "$installed_files" -lt 3 ]; then
		say "An incomplete Koteli installation was found in ${install_dir}."
	fi
	choose_existing_action
fi

case "$action" in
	uninstall)
		uninstall_koteli
		exit 0
		;;
	cancel)
		say "No changes were made."
		exit 0
		;;
	repair)
		say "Repairing Koteli in ${install_dir}..."
		;;
	update)
		say "Updating Koteli in ${install_dir}..."
		;;
esac

if command -v curl >/dev/null 2>&1; then
	download() {
		curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 \
			--output "$2" "$1"
	}
elif command -v wget >/dev/null 2>&1; then
	download() {
		wget --quiet --tries=3 --timeout=15 --output-document="$2" "$1"
	}
else
	fail "curl or wget is required"
fi

temp_root="${TMPDIR:-/tmp}"
temp_dir="$(mktemp -d "${temp_root%/}/koteli-install.XXXXXX")" || fail "could not create a temporary directory"

cleanup() {
	rm -rf "$temp_dir"
}
trap cleanup EXIT HUP INT TERM

validate_binary() {
	binary_path="$1"
	binary_name="$2"

	[ -s "$binary_path" ] || fail "$binary_name is empty; a build may not be published for ${platform}/${architecture} yet"

	magic="$(od -An -tx1 -N4 "$binary_path" 2>/dev/null | tr -d ' \n')"
	case "$platform:$magic" in
		linux:7f454c46)
			;;
		macos:cffaedfe | macos:feedfacf | macos:cafebabe | macos:bebafeca | macos:cafebabf | macos:bfbafeca)
			;;
		*)
			fail "$binary_name is not a valid ${platform} executable; the download may be unavailable or corrupt"
			;;
	esac
}

for binary in $binaries; do
	url="${download_base}/${architecture}/${platform}/${binary}"
	destination="${temp_dir}/${binary}"
	say "Downloading ${binary} for ${platform}/${architecture}..."
	if ! download "$url" "$destination"; then
		fail "could not download $url; a build may not be published for this platform yet"
	fi
	validate_binary "$destination" "$binary"
done

mkdir -p "$install_dir" || fail "could not create $install_dir"

for binary in $binaries; do
	if command -v install >/dev/null 2>&1; then
		install -m 0755 "${temp_dir}/${binary}" "${install_dir}/${binary}"
	else
		cp "${temp_dir}/${binary}" "${install_dir}/${binary}"
		chmod 0755 "${install_dir}/${binary}"
	fi
done

say ""
case "$action" in
	install) result="installed" ;;
	repair) result="repaired" ;;
	update) result="updated" ;;
esac
say "Koteli was ${result} in ${install_dir}."
say ""

case ":${PATH:-}:" in
	*":${install_dir}:"*)
		;;
	*)
	say "Add the install directory to PATH before opening a new terminal:"
	say "  export PATH=\"${install_dir}:\$PATH\""
	say ""
		;;
esac

say "Start the daemon in one terminal:"
say "  kxaid"
say "Then start Koteli in another terminal:"
say "  koteli"
