# koteli
kxki coding intelligence

# READ BEFORE USE THIS TOOL
>[!WARNING]
>this is currently in test build so not even pre-release. this still not include any security wall(for example prompt-injection, sandbox, security-token&context-safety-filter, command-filter etc.)
>Install or use at your own risk.

# Installation

The native installer downloads both Koteli and its `kxaid` daemon. The
current published native build is Windows x64; other platforms fail cleanly
until their binaries are added to this repository.

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

After installation, start `kxaid` in one terminal and `koteli` in another.

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

Uninstall displays Koteli's exact user-state compatibility path and asks
`Remove Koteli user configuration and state? [y/N]`. The default is No.
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

To remove the compatible Koteli user state too, use
`KOTELI_REMOVE_CONFIG=yes`. The `ai.kxki.dev` commands shown above remain the
canonical hosted installer commands.
