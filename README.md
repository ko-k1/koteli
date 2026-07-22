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

Running a native installer again detects the existing installation and offers
Update, Repair, Uninstall, or Cancel. Uninstall asks before removing Koteli's
user configuration and state; project-local `.kxai` and `.koteli` directories
are always preserved.

Set `KOTELI_INSTALL_DIR` to choose a custom destination. Maintainers can also
set `KOTELI_REF` or `KOTELI_DOWNLOAD_BASE` to install from a tag, branch, or
artifact mirror. On Windows, set `KOTELI_NO_PATH_UPDATE=1` to leave the user
`PATH` unchanged. For non-interactive use, set `KOTELI_ACTION` to `update`,
`repair`, `uninstall`, or `cancel`; combine `KOTELI_ACTION=uninstall` with
`KOTELI_REMOVE_CONFIG=yes` to remove user configuration without a prompt.
