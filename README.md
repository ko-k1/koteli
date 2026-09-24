# Koteli / kəʊˈtéli
**K**xki **Co**ding In**telli**gence

# READ BEFORE USE THIS TOOL
>[!WARNING]
>this is currently in test build so not even pre-release. this still not include any security wall(for example prompt-injection, sandbox, security-token&context-safety-filter, command-filter etc.)
>Install or use at your own risk.

# Installation

The native installer downloads both Koteli and its `kotelid` daemon. macOS and
Linux share `install.sh`, while each platform keeps its own executable format:
Linux uses ELF and macOS uses Mach-O. On macOS, Intel models select the `x64`
build from `amd64/macos`, and Apple Silicon selects the `arm64` build from
`aarch64/macos` (including when the installer is launched through Rosetta).
An unavailable platform build fails cleanly instead of using a binary from a
different operating system.

### Install Koteli in a terminal

  - **macOS/Linux:**
    ```bash
    curl -fsSL https://ai.kxki.dev/install.sh | sh
    ```

  - **Windows:**
    ```powershell
    irm https://ai.kxki.dev/install.ps1 | iex
    ```

  - **Bun (Recommended):**
    ```bash
    bun add -g @kxki-dev/koteli
    ```

  - **NPM (Deprecated):**
    ```bash
    npm install -g @kxki-dev/koteli
    ```

After installation, start `kotelid` in one terminal and `koteli` in another, or
run `kotelid --daemonize` to start the daemon in the background.

Koteli keeps its user configuration and state in `~/.koteli`
(`%USERPROFILE%\.koteli` on Windows), including the running daemon's endpoint
record, its per-start client token, and its log.

Upgrading from a build whose daemon was called `kxaid`: Update and Repair
install `kotelid` and remove the old `kxaid` binary. An installation that still
holds only `kxaid` is recognized and repaired.

Running a native installer again opens a compact installed-app manager:

```text
  [ Update    ] refresh both binaries
  [ Repair    ] reinstall both binaries
  [ Uninstall ] remove binaries; configuration is handled separately
  [ Cancel    ] make no changes
```

In a capable terminal, use Up/Down, Enter, Escape, or the number keys. Narrow
terminals and terminals without safe cursor or key support receive a numbered
menu instead. The installer leaves its transcript visible; it never switches
to an alternate screen or clears completed output.

Redirected output and runs with a nonempty `CI`, `TERM=dumb`, or `NO_COLOR`
(including an empty `NO_COLOR`) use stable ASCII-only output without animation
or terminal control sequences. Otherwise, color is enabled on a real terminal,
with Unicode decoration only when its output encoding is UTF-8.

Uninstall displays Koteli's exact user-state path, `~/.koteli`, and, when it
still exists, the legacy `kxai` state directory used by earlier builds, then
asks `Remove Koteli user configuration and state? [y/N]`. The default is No;
Yes removes both. Uninstall also removes a leftover `kxaid` binary.
Project-local `.kxai` and `.koteli` directories are never removed.

### Native installer automation

- `KOTELI_INSTALL_DIR` selects the binary destination.
- `KOTELI_REPOSITORY` and `KOTELI_REF` select a GitHub repository and ref.
- `KOTELI_DOWNLOAD_BASE` replaces the complete artifact base URL.
- `KOTELI_ACTION` bypasses the manager with `update`, `repair`, `uninstall`, or
  `cancel`. The existing `install` value remains a repair alias when binaries
  are already present.
- `KOTELI_REMOVE_CONFIG` accepts `yes`/`no`, `true`/`false`, `y`/`n`, or
  `1`/`0`. It is validated before uninstall removes anything.
- On Windows, `KOTELI_NO_PATH_UPDATE=1` leaves both the user and current-process
  `PATH` unchanged.

For example, a non-interactive binary-only uninstall is:

```bash
KOTELI_ACTION=uninstall KOTELI_REMOVE_CONFIG=no sh install.sh
```

To remove the Koteli user state too, use
`KOTELI_REMOVE_CONFIG=yes`. The `ai.kxki.dev` commands shown above remain the
canonical hosted installer commands.
