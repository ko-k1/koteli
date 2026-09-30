# AGENTS.md — koteli (installer + binary-drop repo)

> Binary-distribution repo for `koteli` CLI + `kotelid` daemon. There is no
> application build step. Agents work on `install.sh`, `install.ps1`, and
> `tests/`. Binaries under `aarch64|amd64/` are release artifacts, committed.

## Layout

- `install.sh` — POSIX `sh` installer (macOS/Linux, 888 lines).
- `install.ps1` — Windows installer, PowerShell 5.1 + 7 compatible.
- `tests/test_installers.py` — zero-dependency stdlib integration tests.
- `tests/conpty_helper.cs` — ConPTY driver, inbox `csc.exe` only.
- `tests/snapshots/{posix,windows}-install.txt` — fresh-install plain transcripts.
- `aarch64|amd64/{linux,macos,win}/` — 12 committed binaries (`*.exe` on win).
- `.github/workflows/installers.yml` — CI matrix (source of truth for checks).
- `.agents/` — empty, reserved, currently unused. Do not rely on it.

## Commands

```powershell
# Windows (this repo's dev host): `python`, not `python3`
python -m unittest -v tests/test_installers.py
# POSIX:
python3 -m unittest -v tests/test_installers.py
# Single test (safe form; no __init__.py in tests/):
python -m unittest -v tests/test_installers.py -k test_cancel_has_no_network_or_file_changes
```

```powershell
# PowerShell syntax check, both shells (from CI):
$errors = $null
[Management.Automation.Language.Parser]::ParseFile("$pwd\install.ps1", [ref]$null, [ref]$errors) > $null
if ($errors.Count) { $errors | ForEach-Object { Write-Error $_.Message }; exit 1 }
```

```bash
# POSIX syntax check — CI or Git Bash only, not native PowerShell:
/bin/sh -n install.sh
```

## Conventions — install.sh

- POSIX `sh` only, `set -eu`. No bashisms.
- Keep plain-ASCII path working: `CI`, `TERM=dumb`, or `NO_COLOR` (even empty)
  disables color/animation; never use alternate-screen or clear sequences.
- Stage names are contract: `Detect / Fetch / Validate format / Install-Remove / PATH`.

## Conventions — install.ps1

- Must stay Windows PowerShell 5.1 compatible. `Set-StrictMode Latest`,
  `$ErrorActionPreference = 'Stop'`.
- PATH edits only via `.koteli-path-added` marker file. Honor
  `KOTELI_NO_PATH_UPDATE=1`.
- Env vars: `KOTELI_REPOSITORY`, `KOTELI_REF`, `KOTELI_DOWNLOAD_BASE`,
  `KOTELI_INSTALL_DIR`, `KOTELI_ACTION` (`update|repair|install→repair|cancel|uninstall`),
  `KOTELI_REMOVE_CONFIG` (`yes/no` family).

## Conventions — tests

- Stdlib only (no pytest/deps). Isolate via temp workspace: redirect
  `HOME/USERPROFILE/LOCALAPPDATA/TEMP`, force `CI=1`, serve fixtures from local
  `http.server`. Never touch real `~/.koteli` or real user PATH registry.
- Snapshots: edit `tests/snapshots/*` only for intentional transcript changes.
  Normalize `<INSTALL_DIR> <CONFIG_DIR> <BASE_URL> <ARCH> <SYSTEM>`; backslash → slash.

## Binary update procedure

- Artifact URL layout: `{base}/{amd64|aarch64}/{linux|macos|win}/{koteli|kotelid}[.exe]`.
  macOS display names are `x64`/`arm64`; Rosetta (`sysctl.proc_translated=1`) selects `aarch64`.
- Replace `koteli`+`kotelid` as a matched pair per arch/platform. Verify magic bytes
  before commit: ELF `7f454c46` (linux), Mach-O (macos), `MZ` (win).
- Run the full unittest matrix after any binary swap. Prefer one arch/platform per
  commit (suggestion, keeps diffs reviewable).

## Safety / do-not

- Config deletion is allowlisted to exact `~/.koteli` (+ legacy `.../kxai/tui/.kxai`).
  Never delete project-local `.kxai`/`.koteli`. Never widen the `rm -rf` boundary.
- Validation order matters: validate downloads in temp dir before touching the
  install dir; `koteli-install.*` temp dirs must always be cleaned (incl. signals).
- Do not commit `.tokensave/`, `.serena/`, or `__pycache__/`. Respect LF for `*.sh`.

## Where to look

- Receipt keys: `Action / Binaries / Destination / PATH / Koteli state / Legacy kxaid`.
- Legacy `kxaid[.exe]` (now `kotelid`): update/repair/uninstall must remove it.
- Details: `README.md` (env vars, manager menu), stage logic in installers, cases in `test_installers.py`.
