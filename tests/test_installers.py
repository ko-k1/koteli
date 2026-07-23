"""Zero-dependency integration tests for the native Koteli installers."""

from __future__ import annotations

import base64
import contextlib
import http.server
import os
import pathlib
import platform
import select
import shutil
import signal
import socketserver
import struct
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
POSIX_INSTALLER = ROOT / "install.sh"
WINDOWS_INSTALLER = ROOT / "install.ps1"
SNAPSHOTS = ROOT / "tests" / "snapshots"

ELF = b"\x7fELF" + b"\x00" * 60
MACH_O = b"\xcf\xfa\xed\xfe" + b"\x00" * 60
MZ = b"MZ" + b"\x00" * 62


class _FixtureHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self.server.hits.append(self.path)  # type: ignore[attr-defined]
        fixture = self.server.fixtures.get(self.path)  # type: ignore[attr-defined]
        if fixture is None:
            self.send_error(404)
            return
        if fixture == "drop":
            self.send_response(200)
            self.send_header("Content-Length", "65536")
            self.end_headers()
            self.wfile.write(ELF[:8])
            self.wfile.flush()
            self.close_connection = True
            return
        if fixture == "interrupt":
            self.send_response(200)
            self.send_header("Content-Length", "65536")
            self.end_headers()
            self.wfile.write(ELF)
            self.wfile.flush()
            time.sleep(10)
            return
        status, body = fixture
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: object) -> None:
        return


class _ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


class FixtureServer(contextlib.AbstractContextManager["FixtureServer"]):
    def __init__(self, fixtures: dict[str, tuple[int, bytes] | str]) -> None:
        self._httpd = _ThreadingServer(("127.0.0.1", 0), _FixtureHandler)
        self._httpd.fixtures = fixtures
        self._httpd.hits = []
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        host, port = self._httpd.server_address
        return f"http://{host}:{port}"

    @property
    def hits(self) -> list[str]:
        return self._httpd.hits

    def __enter__(self) -> "FixtureServer":
        self._thread.start()
        return self

    def __exit__(self, *_exc: object) -> None:
        self._httpd.shutdown()
        self._httpd.server_close()
        self._thread.join(timeout=5)


def clean_environment() -> dict[str, str]:
    env = os.environ.copy()
    for name in tuple(env):
        if name.startswith("KOTELI_") or name in {"NO_COLOR", "CI"}:
            env.pop(name, None)
    env["CI"] = "1"
    env["TERM"] = "xterm-256color"
    return env


def assert_plain(test: unittest.TestCase, raw: bytes) -> str:
    without_line_endings = raw.replace(b"\r\n", b"\n")
    test.assertNotIn(b"\x1b", raw)
    test.assertNotIn(b"\r", without_line_endings)
    text = raw.decode("utf-8", errors="replace")
    test.assertTrue(
        all(ord(character) < 128 for character in text),
        f"plain transcript was not ASCII-only:\n{text}",
    )
    return text.replace("\r\n", "\n")


def normalize_transcript(
    text: str,
    *,
    install_dir: pathlib.Path,
    config_dir: pathlib.Path,
    base_url: str,
) -> str:
    replacements = (
        (str(install_dir), "<INSTALL_DIR>"),
        (str(config_dir), "<CONFIG_DIR>"),
        (base_url, "<BASE_URL>"),
    )
    normalized = text
    for source, target in replacements:
        normalized = normalized.replace(source, target)
    normalized = normalized.replace("\\", "/")
    return normalized


def fixture_map(
    system: str,
    architecture: str,
    *,
    first: bytes,
    second: bytes,
) -> dict[str, tuple[int, bytes]]:
    suffix = ".exe" if system == "win" else ""
    return {
        f"/{architecture}/{system}/koteli{suffix}": (200, first),
        f"/{architecture}/{system}/kxaid{suffix}": (200, second),
    }


@unittest.skipUnless(os.name == "posix", "POSIX installer tests")
class PosixInstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workspace = pathlib.Path(tempfile.mkdtemp(prefix="koteli-posix-test-"))
        self.addCleanup(shutil.rmtree, self.workspace, True)
        self.install_dir = self.workspace / "bin"
        self.home = self.workspace / "home"
        self.temp_dir = self.workspace / "tmp"
        self.home.mkdir()
        self.temp_dir.mkdir()
        machine = platform.machine().lower()
        self.architecture = "aarch64" if machine in {"arm64", "aarch64"} else "amd64"
        self.system = "macos" if platform.system() == "Darwin" else "linux"
        self.fixture = MACH_O if self.system == "macos" else ELF

    def environment(self, base_url: str) -> dict[str, str]:
        env = clean_environment()
        env.update(
            {
                "HOME": str(self.home),
                "TMPDIR": str(self.temp_dir),
                "KOTELI_INSTALL_DIR": str(self.install_dir),
                "KOTELI_DOWNLOAD_BASE": base_url,
            }
        )
        return env

    def run_installer(
        self, env: dict[str, str], *, input_bytes: bytes = b""
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            ["/bin/sh", str(POSIX_INSTALLER)],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=30,
            check=False,
        )

    def test_fresh_install_plain_snapshot(self) -> None:
        fixtures = fixture_map(
            self.system,
            self.architecture,
            first=self.fixture,
            second=self.fixture,
        )
        with FixtureServer(fixtures) as server:
            result = self.run_installer(self.environment(server.base_url))
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            output = assert_plain(self, result.stdout + result.stderr)
            config_dir = self.home / ".local" / "state" / "kxai" / "tui" / ".kxai"
            normalized = normalize_transcript(
                output,
                install_dir=self.install_dir,
                config_dir=config_dir,
                base_url=server.base_url,
            )
            expected = (SNAPSHOTS / "posix-install.txt").read_text(encoding="utf-8")
            expected = expected.replace("<SYSTEM>", self.system).replace(
                "<ARCH>", self.architecture
            )
            self.assertEqual(normalized, expected)
        for binary in ("koteli", "kxaid"):
            path = self.install_dir / binary
            self.assertTrue(path.is_file())
            self.assertTrue(os.access(path, os.X_OK))

    def test_second_binary_validation_failure_installs_nothing_and_cleans_up(self) -> None:
        fixtures = fixture_map(
            self.system,
            self.architecture,
            first=self.fixture,
            second=b"not an executable",
        )
        with FixtureServer(fixtures) as server:
            result = self.run_installer(self.environment(server.base_url))
        self.assertNotEqual(result.returncode, 0)
        combined = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[error] Validate format - kxaid:", combined)
        self.assertFalse((self.install_dir / "koteli").exists())
        self.assertEqual(list(self.temp_dir.glob("koteli-install.*")), [])

    def test_empty_and_missing_downloads_fail_at_fetch_or_validation(self) -> None:
        cases = {
            "empty": {
                f"/{self.architecture}/{self.system}/koteli": (200, b""),
                f"/{self.architecture}/{self.system}/kxaid": (
                    200,
                    self.fixture,
                ),
            },
            "missing": {
                f"/{self.architecture}/{self.system}/kxaid": (
                    200,
                    self.fixture,
                ),
            },
            "interrupted": {
                f"/{self.architecture}/{self.system}/koteli": "drop",
                f"/{self.architecture}/{self.system}/kxaid": (
                    200,
                    self.fixture,
                ),
            },
        }
        for label, fixtures in cases.items():
            with self.subTest(label=label), FixtureServer(fixtures) as server:
                result = self.run_installer(self.environment(server.base_url))
                self.assertNotEqual(result.returncode, 0)
                combined = assert_plain(self, result.stdout + result.stderr)
                self.assertIn("[error]", combined)
                self.assertFalse((self.install_dir / "koteli").exists())

    def test_cancel_downloads_nothing(self) -> None:
        self.install_dir.mkdir()
        (self.install_dir / "koteli").write_bytes(self.fixture)
        (self.install_dir / "kxaid").write_bytes(self.fixture)
        with FixtureServer({}) as server:
            env = self.environment(server.base_url)
            env["KOTELI_ACTION"] = "cancel"
            result = self.run_installer(env)
            self.assertEqual(server.hits, [])
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Changes: none", output)

    def test_invalid_remove_config_value_is_non_destructive(self) -> None:
        self.install_dir.mkdir()
        binary_paths = [self.install_dir / "koteli", self.install_dir / "kxaid"]
        for path in binary_paths:
            path.write_bytes(self.fixture)
        state = self.home / ".local" / "state" / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        (state / "state.db").write_text("keep", encoding="utf-8")
        env = self.environment("http://127.0.0.1:9")
        env.update(
            {
                "KOTELI_ACTION": "uninstall",
                "KOTELI_REMOVE_CONFIG": "sometimes",
            }
        )
        result = self.run_installer(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(path.exists() for path in binary_paths))
        self.assertTrue((state / "state.db").exists())

    def test_uninstall_yes_removes_state_but_preserves_project_directories(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(self.fixture)
        state = self.home / ".local" / "state" / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        project = self.workspace / "project"
        (project / ".kxai").mkdir(parents=True)
        (project / ".koteli").mkdir()
        env = self.environment("http://127.0.0.1:9")
        env.update(
            {
                "KOTELI_ACTION": "uninstall",
                "KOTELI_REMOVE_CONFIG": "yes",
            }
        )
        result = self.run_installer(env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Koteli state: removed", output)
        self.assertFalse(state.exists())
        self.assertTrue((project / ".kxai").is_dir())
        self.assertTrue((project / ".koteli").is_dir())

    def test_install_action_alias_repairs_an_existing_installation(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        fixtures = fixture_map(
            self.system,
            self.architecture,
            first=self.fixture,
            second=self.fixture,
        )
        with FixtureServer(fixtures) as server:
            env = self.environment(server.base_url)
            env["KOTELI_ACTION"] = "install"
            result = self.run_installer(env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Action: repaired", output)

    def test_path_stage_reports_an_existing_path_entry(self) -> None:
        fixtures = fixture_map(
            self.system,
            self.architecture,
            first=self.fixture,
            second=self.fixture,
        )
        with FixtureServer(fixtures) as server:
            env = self.environment(server.base_url)
            env["PATH"] = f"{self.install_dir}{os.pathsep}{env['PATH']}"
            result = self.run_installer(env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] PATH: already available", output)
        self.assertNotIn("[next] Add to PATH", output)

    def test_signals_preserve_shell_status_and_remove_temporary_files(self) -> None:
        if not hasattr(os, "killpg"):
            self.skipTest("process-group signals are unavailable")
        signal_cases = (
            (signal.SIGHUP, 129),
            (signal.SIGINT, 130),
            (signal.SIGTERM, 143),
        )
        for sent_signal, expected_status in signal_cases:
            fixtures = {
                f"/{self.architecture}/{self.system}/koteli": "interrupt",
                f"/{self.architecture}/{self.system}/kxaid": (
                    200,
                    self.fixture,
                ),
            }
            with self.subTest(sent_signal=sent_signal), FixtureServer(fixtures) as server:
                process = subprocess.Popen(
                    ["/bin/sh", str(POSIX_INSTALLER)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=self.environment(server.base_url),
                    start_new_session=True,
                )
                deadline = time.monotonic() + 10
                while not server.hits and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(server.hits, "installer never began the interrupted fetch")
                os.killpg(process.pid, sent_signal)
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(
                    process.returncode,
                    expected_status,
                    (stdout + stderr).decode(errors="replace"),
                )
                self.assertEqual(list(self.temp_dir.glob("koteli-install.*")), [])

    def _run_pty(
        self,
        env: dict[str, str],
        input_after_menu: bytes,
        *,
        columns: int = 80,
    ) -> tuple[int, bytes, list[int], list[int]]:
        import fcntl
        import pty
        import termios

        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, columns, 0, 0))
        before = termios.tcgetattr(slave)

        def establish_controlling_terminal() -> None:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        process = subprocess.Popen(
            ["/bin/sh", str(POSIX_INSTALLER)],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
            close_fds=True,
            preexec_fn=establish_controlling_terminal,
        )
        transcript = bytearray()
        sent = False
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    chunk = b""
                if chunk:
                    transcript.extend(chunk)
                    if not sent and (
                        b"Use Up/Down" in transcript
                        or b"Choose an action" in transcript
                    ):
                        os.write(master, input_after_menu)
                        sent = True
            if process.poll() is not None:
                while True:
                    ready, _, _ = select.select([master], [], [], 0)
                    if not ready:
                        break
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    transcript.extend(chunk)
                break
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
            self.fail(f"PTY installer timed out:\n{transcript.decode(errors='replace')}")
        after = termios.tcgetattr(slave)
        return process.returncode, bytes(transcript), before, after

    @unittest.skipUnless(
        shutil.which("tput") and shutil.which("stty"), "terminal tools are required"
    )
    def test_pty_arrow_selection_preserves_transcript_and_restores_terminal(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        fixtures = fixture_map(
            self.system,
            self.architecture,
            first=self.fixture,
            second=self.fixture,
        )
        with FixtureServer(fixtures) as server:
            env = self.environment(server.base_url)
            env.pop("CI", None)
            env["LANG"] = "C.UTF-8"
            returncode, raw, before, after = self._run_pty(env, b"\x1b[B\r")
        self.assertEqual(returncode, 0, raw.decode(errors="replace"))
        text = raw.decode("utf-8", errors="replace")
        self.assertIn("Selected: Repair", text)
        self.assertIn("Action: repaired", text)
        self.assertLess(text.find("Koteli"), text.find("Selected: Repair"))
        self.assertNotIn("\x1b[2J", text)
        self.assertNotIn("\x1b[?1049", text)
        import termios

        terminal_flags = termios.ECHO | termios.ICANON
        self.assertEqual(before[3] & terminal_flags, after[3] & terminal_flags)

    @unittest.skipUnless(
        shutil.which("tput") and shutil.which("stty"), "terminal tools are required"
    )
    def test_narrow_pty_uses_numbered_menu_and_blank_cancels(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        env = self.environment("http://127.0.0.1:9")
        env.pop("CI", None)
        returncode, raw, _before, _after = self._run_pty(env, b"\r", columns=40)
        self.assertEqual(returncode, 0, raw.decode(errors="replace"))
        text = raw.decode(errors="replace")
        self.assertIn("1) Update", text)
        self.assertIn("Selected: Cancel", text)
        self.assertNotIn("\x1b[4A", text)

    @unittest.skipUnless(
        shutil.which("tput") and shutil.which("stty"), "terminal tools are required"
    )
    def test_missing_cursor_capability_falls_back_below_existing_output(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        env = self.environment("http://127.0.0.1:9")
        env.pop("CI", None)
        env["TERM"] = "koteli-no-such-terminal"
        returncode, raw, _before, _after = self._run_pty(env, b"\r")
        self.assertEqual(returncode, 0, raw.decode(errors="replace"))
        text = raw.decode(errors="replace")
        self.assertIn("Koteli", text)
        self.assertIn("1) Update", text)
        self.assertIn("Selected: Cancel", text)
        self.assertLess(text.find("Koteli"), text.find("1) Update"))

    @unittest.skipUnless(
        shutil.which("tput") and shutil.which("stty"), "terminal tools are required"
    )
    def test_plain_mode_triggers_remain_ascii_inside_a_pty(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        variants = (
            ("ci", {"CI": "true"}),
            ("dumb", {"TERM": "dumb"}),
            ("no-color-empty", {"NO_COLOR": ""}),
        )
        for label, additions in variants:
            with self.subTest(label=label):
                env = self.environment("http://127.0.0.1:9")
                env.pop("CI", None)
                env["LANG"] = "C.UTF-8"
                env["KOTELI_ACTION"] = "cancel"
                env.update(additions)
                returncode, raw, _before, _after = self._run_pty(env, b"")
                self.assertEqual(returncode, 0, raw.decode(errors="replace"))
                text = assert_plain(self, raw)
                self.assertIn("== Koteli ==", text)

    @unittest.skipUnless(
        shutil.which("tput") and shutil.which("stty"), "terminal tools are required"
    )
    def test_interactive_uninstall_blank_config_answer_preserves_state(self) -> None:
        self.install_dir.mkdir()
        for binary in ("koteli", "kxaid"):
            (self.install_dir / binary).write_bytes(b"old")
        state = self.home / ".local" / "state" / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        (state / "state.db").write_text("keep", encoding="utf-8")
        env = self.environment("http://127.0.0.1:9")
        env.pop("CI", None)
        env["LANG"] = "C.UTF-8"
        returncode, raw, _before, _after = self._run_pty(env, b"3\r")
        self.assertEqual(returncode, 0, raw.decode(errors="replace"))
        text = raw.decode("utf-8", errors="replace")
        self.assertIn("Remove Koteli user configuration and state? [y/N]", text)
        self.assertIn("Koteli state", text)
        self.assertIn("preserved", text)
        self.assertTrue((state / "state.db").is_file())


@unittest.skipUnless(os.name == "nt", "Windows installer tests")
class WindowsInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shells = [
            executable
            for executable in (shutil.which("powershell"), shutil.which("pwsh"))
            if executable
        ]
        if not cls.shells:
            raise unittest.SkipTest("PowerShell is unavailable")
        windows_directory = pathlib.Path(os.environ.get("WINDIR", r"C:\Windows"))
        cls.csharp_compiler = next(
            (
                candidate
                for candidate in (
                    windows_directory
                    / "Microsoft.NET"
                    / "Framework64"
                    / "v4.0.30319"
                    / "csc.exe",
                    windows_directory
                    / "Microsoft.NET"
                    / "Framework"
                    / "v4.0.30319"
                    / "csc.exe",
                )
                if candidate.is_file()
            ),
            None,
        )
        cls.conpty_directory = pathlib.Path(
            tempfile.mkdtemp(prefix="koteli-conpty-build-")
        )
        cls.addClassCleanup(shutil.rmtree, cls.conpty_directory, True)
        cls.conpty_helper = cls.conpty_directory / "conpty_helper.exe"
        if cls.csharp_compiler:
            compilation = subprocess.run(
                [
                    cls.csharp_compiler,
                    "/nologo",
                    f"/out:{cls.conpty_helper}",
                    ROOT / "tests" / "conpty_helper.cs",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if compilation.returncode != 0:
                cls.conpty_helper = None
        else:
            cls.conpty_helper = None

    def setUp(self) -> None:
        self.workspace = pathlib.Path(tempfile.mkdtemp(prefix="koteli-win-test-"))
        self.addCleanup(shutil.rmtree, self.workspace, True)
        self.install_dir = self.workspace / "bin"
        self.local_app_data = self.workspace / "local"
        self.temp_dir = self.workspace / "tmp"
        self.local_app_data.mkdir()
        self.temp_dir.mkdir()
        self.architecture = (
            "aarch64" if platform.machine().lower() in {"arm64", "aarch64"} else "amd64"
        )

    def environment(self, base_url: str) -> dict[str, str]:
        env = clean_environment()
        env.update(
            {
                "LOCALAPPDATA": str(self.local_app_data),
                "APPDATA": str(self.local_app_data),
                "TEMP": str(self.temp_dir),
                "TMP": str(self.temp_dir),
                "KOTELI_INSTALL_DIR": str(self.install_dir),
                "KOTELI_DOWNLOAD_BASE": base_url,
                "KOTELI_NO_PATH_UPDATE": "1",
            }
        )
        return env

    def run_installer(
        self, shell: str, env: dict[str, str]
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-File", WINDOWS_INSTALLER],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=45,
            check=False,
        )

    @staticmethod
    def read_real_user_path() -> str | None:
        import winreg

        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
                value, _kind = winreg.QueryValueEx(key, "Path")
                return value
        except FileNotFoundError:
            return None

    def test_fresh_install_plain_snapshot_and_real_user_path_unchanged(self) -> None:
        fixtures = fixture_map(
            "win", self.architecture, first=MZ, second=MZ
        )
        for shell in self.shells:
            with self.subTest(shell=pathlib.Path(shell).name):
                shutil.rmtree(self.install_dir, ignore_errors=True)
                with FixtureServer(fixtures) as server:
                    env = self.environment(server.base_url)
                    before_path = self.read_real_user_path()
                    result = self.run_installer(shell, env)
                    after_path = self.read_real_user_path()
                    self.assertEqual(before_path, after_path)
                    self.assertEqual(
                        result.returncode, 0, result.stderr.decode(errors="replace")
                    )
                    output = assert_plain(self, result.stdout + result.stderr)
                    config_dir = (
                        self.local_app_data / "kxai" / "tui" / ".kxai"
                    )
                    normalized = normalize_transcript(
                        output,
                        install_dir=self.install_dir,
                        config_dir=config_dir,
                        base_url=server.base_url,
                    )
                    expected = (SNAPSHOTS / "windows-install.txt").read_text(
                        encoding="utf-8"
                    ).replace("<ARCH>", self.architecture)
                    self.assertEqual(normalized, expected)
                self.assertTrue((self.install_dir / "koteli.exe").is_file())
                self.assertTrue((self.install_dir / "kxaid.exe").is_file())

    def test_empty_and_missing_downloads_fail_cleanly(self) -> None:
        cases = {
            "empty": {
                f"/{self.architecture}/win/koteli.exe": (200, b""),
                f"/{self.architecture}/win/kxaid.exe": (200, MZ),
            },
            "missing": {
                f"/{self.architecture}/win/kxaid.exe": (200, MZ),
            },
            "interrupted": {
                f"/{self.architecture}/win/koteli.exe": "drop",
                f"/{self.architecture}/win/kxaid.exe": (200, MZ),
            },
        }
        for label, fixtures in cases.items():
            with self.subTest(label=label), FixtureServer(fixtures) as server:
                shutil.rmtree(self.install_dir, ignore_errors=True)
                result = self.run_installer(
                    self.shells[0], self.environment(server.base_url)
                )
                self.assertNotEqual(result.returncode, 0)
                combined = assert_plain(self, result.stdout + result.stderr)
                self.assertIn("[error]", combined)
                self.assertFalse((self.install_dir / "koteli.exe").exists())

    def test_second_binary_failure_does_not_replace_existing_files(self) -> None:
        self.install_dir.mkdir()
        (self.install_dir / "koteli.exe").write_bytes(b"old koteli")
        (self.install_dir / "kxaid.exe").write_bytes(b"old kxaid")
        fixtures = fixture_map(
            "win", self.architecture, first=MZ, second=b"bad"
        )
        for shell in self.shells:
            with self.subTest(shell=pathlib.Path(shell).name):
                (self.install_dir / "koteli.exe").write_bytes(b"old koteli")
                (self.install_dir / "kxaid.exe").write_bytes(b"old kxaid")
                with FixtureServer(fixtures) as server:
                    env = self.environment(server.base_url)
                    env["KOTELI_ACTION"] = "update"
                    result = self.run_installer(shell, env)
                self.assertNotEqual(result.returncode, 0)
                combined = assert_plain(self, result.stdout + result.stderr)
                self.assertIn("[error] Validate format -", combined)
                self.assertEqual(
                    (self.install_dir / "koteli.exe").read_bytes(), b"old koteli"
                )
                self.assertEqual(
                    (self.install_dir / "kxaid.exe").read_bytes(), b"old kxaid"
                )
                self.assertEqual(list(self.temp_dir.glob("koteli-install-*")), [])

    def test_cancel_has_no_network_or_file_changes(self) -> None:
        self.install_dir.mkdir()
        binaries = (self.install_dir / "koteli.exe", self.install_dir / "kxaid.exe")
        for path in binaries:
            path.write_bytes(b"old")
        with FixtureServer({}) as server:
            env = self.environment(server.base_url)
            env["KOTELI_ACTION"] = "cancel"
            result = self.run_installer(self.shells[0], env)
            self.assertEqual(server.hits, [])
        self.assertEqual(result.returncode, 0)
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Changes: none", output)
        self.assertTrue(all(path.read_bytes() == b"old" for path in binaries))

    def test_invalid_remove_config_is_validated_before_binary_removal(self) -> None:
        self.install_dir.mkdir()
        binaries = (self.install_dir / "koteli.exe", self.install_dir / "kxaid.exe")
        for path in binaries:
            path.write_bytes(b"old")
        state = self.local_app_data / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        (state / "state.db").write_text("keep", encoding="utf-8")
        env = self.environment("http://127.0.0.1:9")
        env.update(
            {
                "KOTELI_ACTION": "uninstall",
                "KOTELI_REMOVE_CONFIG": "sometimes",
            }
        )
        result = self.run_installer(self.shells[0], env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(path.exists() for path in binaries))
        self.assertTrue((state / "state.db").exists())

    def test_uninstall_default_automation_preserves_config(self) -> None:
        self.install_dir.mkdir()
        for name in ("koteli.exe", "kxaid.exe"):
            (self.install_dir / name).write_bytes(b"old")
        state = self.local_app_data / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        (state / "state.db").write_text("keep", encoding="utf-8")
        env = self.environment("http://127.0.0.1:9")
        env["KOTELI_ACTION"] = "uninstall"
        result = self.run_installer(self.shells[0], env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Koteli state: preserved", output)
        self.assertTrue((state / "state.db").exists())

    def test_install_action_alias_repairs_existing_binaries(self) -> None:
        self.install_dir.mkdir()
        for name in ("koteli.exe", "kxaid.exe"):
            (self.install_dir / name).write_bytes(b"old")
        fixtures = fixture_map("win", self.architecture, first=MZ, second=MZ)
        with FixtureServer(fixtures) as server:
            env = self.environment(server.base_url)
            env["KOTELI_ACTION"] = "install"
            result = self.run_installer(self.shells[0], env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Action: repaired", output)

    def test_plain_policy_environment_values_emit_no_terminal_controls(self) -> None:
        self.install_dir.mkdir()
        for name in ("koteli.exe", "kxaid.exe"):
            (self.install_dir / name).write_bytes(b"old")
        variants = (
            ("ci", {"CI": "true"}),
            ("dumb", {"TERM": "dumb"}),
            ("no-color-empty", {"NO_COLOR": ""}),
        )
        for label, additions in variants:
            with self.subTest(label=label):
                env = self.environment("http://127.0.0.1:9")
                env["KOTELI_ACTION"] = "cancel"
                env.update(additions)
                result = self.run_installer(self.shells[0], env)
                self.assertEqual(
                    result.returncode, 0, result.stderr.decode(errors="replace")
                )
                output = assert_plain(self, result.stdout + result.stderr)
                self.assertIn("== Koteli ==", output)

    def test_path_add_and_uninstall_remove_use_in_memory_persistence(self) -> None:
        fixtures = fixture_map("win", self.architecture, first=MZ, second=MZ)
        with FixtureServer(fixtures) as server:
            env = self.environment(server.base_url)
            env.pop("KOTELI_NO_PATH_UPDATE", None)
            escaped_installer = str(WINDOWS_INSTALLER).replace("'", "''")
            command_text = f"""
[AppDomain]::CurrentDomain.SetData('KoteliInstaller.UseInMemoryUserPath', $true)
[AppDomain]::CurrentDomain.SetData('KoteliInstaller.InMemoryUserPath', 'C:\\Existing')
& '{escaped_installer}'
[Console]::Out.WriteLine(
    '__PATH_AFTER_ADD__=' +
    [AppDomain]::CurrentDomain.GetData('KoteliInstaller.InMemoryUserPath')
)
$env:KOTELI_ACTION = 'uninstall'
$env:KOTELI_REMOVE_CONFIG = 'no'
& '{escaped_installer}'
[Console]::Out.WriteLine(
    '__PATH_AFTER_REMOVE__=' +
    [AppDomain]::CurrentDomain.GetData('KoteliInstaller.InMemoryUserPath')
)
"""
            encoded_command = base64.b64encode(
                command_text.encode("utf-16-le")
            ).decode("ascii")
            real_path_before = self.read_real_user_path()
            result = subprocess.run(
                [
                    self.shells[0],
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-EncodedCommand",
                    encoded_command,
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=60,
                check=False,
            )
            real_path_after = self.read_real_user_path()
        self.assertEqual(real_path_before, real_path_after)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn(
            f"__PATH_AFTER_ADD__=C:\\Existing;{self.install_dir}",
            output,
        )
        self.assertIn("__PATH_AFTER_REMOVE__=C:\\Existing", output)
        self.assertIn("[result] PATH: added to user PATH", output)
        self.assertIn("[result] PATH: removed", output)

    def test_uninstall_yes_preserves_project_local_directories(self) -> None:
        self.install_dir.mkdir()
        for name in ("koteli.exe", "kxaid.exe"):
            (self.install_dir / name).write_bytes(b"old")
        state = self.local_app_data / "kxai" / "tui" / ".kxai"
        state.mkdir(parents=True)
        project = self.workspace / "project"
        (project / ".kxai").mkdir(parents=True)
        (project / ".koteli").mkdir()
        env = self.environment("http://127.0.0.1:9")
        env.update(
            {
                "KOTELI_ACTION": "uninstall",
                "KOTELI_REMOVE_CONFIG": "yes",
            }
        )
        result = self.run_installer(self.shells[0], env)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        output = assert_plain(self, result.stdout + result.stderr)
        self.assertIn("[result] Koteli state: removed", output)
        self.assertFalse(state.exists())
        self.assertTrue((project / ".kxai").is_dir())
        self.assertTrue((project / ".koteli").is_dir())

    def test_conpty_cancel_keeps_existing_transcript_visible(self) -> None:
        if self.conpty_helper is None:
            self.skipTest("the inbox C# compiler could not build the ConPTY helper")
        if platform.version().split(".")[0] == "6":
            self.skipTest("ConPTY requires Windows 10 or newer")

        self.install_dir.mkdir()
        for name in ("koteli.exe", "kxaid.exe"):
            (self.install_dir / name).write_bytes(b"old")
        env = self.environment("http://127.0.0.1:9")
        env.pop("CI", None)
        env.pop("KOTELI_NO_PATH_UPDATE", None)
        command = [
            str(self.conpty_helper),
            base64.b64encode(b"4\r").decode("ascii"),
            self.shells[0],
            "-NoLogo",
            "-NoProfile",
            "-File",
            str(WINDOWS_INSTALLER),
        ]
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=60,
            check=False,
        )
        if result.returncode == 125:
            self.skipTest(
                "ConPTY is unavailable in this Windows execution environment: "
                + result.stderr.decode(errors="replace")
            )
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        text = result.stdout.decode("utf-8", errors="replace")
        self.assertIn("manage", text)
        self.assertIn("Selected: Cancel", text)
        self.assertIn("Changes", text)
        self.assertLess(text.find("Koteli"), text.find("Selected: Cancel"))
        installer_end = text.find("[result] Changes: none")
        if installer_end < 0:
            installer_end = text.find("Changes: none")
        installer_transcript = text[:installer_end]
        # PowerShell's host may emit its own prompt-control bytes after the
        # script has returned; the installer-owned transcript never does.
        self.assertNotIn("\x1b[2J", installer_transcript)
        self.assertNotIn("\x1b[?1049", installer_transcript)


if __name__ == "__main__":
    unittest.main(verbosity=2)
