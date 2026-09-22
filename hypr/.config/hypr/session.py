#!/usr/bin/env python3
"""Best-effort window launch/layout recovery, not process resurrection."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from typing import Iterator
from urllib.parse import unquote, urlparse

STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "hypr-session"
SNAPSHOT = STATE / "session.json"
SIGNATURE = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
INSTANCE = hashlib.sha256(SIGNATURE.encode()).hexdigest()[:20]
DEBOUNCE_SECONDS = 0.5
EVENT_BUFFER_LIMIT = 262144
FROZEN = STATE / f"frozen-{INSTANCE}.json"
WAIT_SECONDS = 20
TERMINAL_COMMANDS = {"herdr", "claude", "codex", "opencode", "nvim", "vim", "hx", "helix", "lazygit"}


class SessionError(RuntimeError):
    pass


class IPCError(SessionError):
    pass


def report(message: str) -> None:
    print(message, file=sys.stderr)
    with (STATE / "session.log").open("a", encoding="utf-8") as stream:
        stream.write(time.strftime("%Y-%m-%d %H:%M:%S ") + message + "\n")


@contextmanager
def locked(name: str, blocking: bool = True) -> Iterator[None]:
    with (STATE / name).open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError as exc:
            raise SessionError("A watcher already owns this compositor") from exc
        yield


def atomic(path: Path, value: object) -> None:
    fd, name = tempfile.mkstemp(prefix=".session-", dir=STATE)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(STATE, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(name).unlink(missing_ok=True)


def hypr(*args: str) -> str:
    try:
        result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5, check=True)
    except (OSError, subprocess.SubprocessError) as exc:
        error = IPCError if args[0] == "clients" else SessionError
        raise error("Hyprland IPC command failed: " + args[0]) from exc
    if args[0] in {"eval", "dispatch"} and result.stdout.strip().lower() != "ok":
        raise SessionError("Hyprland rejected Lua operation")
    return result.stdout


def lua_string(value: str) -> str:
    delimiter = "="
    while "]" + delimiter + "]" in value:
        delimiter += "="
    return "[" + delimiter + "[" + value + "]" + delimiter + "]"


def clients() -> list[dict]:
    try:
        value = json.loads(hypr("clients", "-j"))
        if not isinstance(value, list) or any(
            not isinstance(c, dict) or not isinstance(c.get("workspace"), dict)
            or not isinstance(c.get("pid"), int) or not isinstance(c.get("address"), str)
            or not isinstance(c.get("class"), str) or not isinstance(c["workspace"].get("id"), int)
            or not isinstance(c["workspace"].get("name"), str) for c in value
        ):
            raise ValueError("invalid client data")
        return [c for c in value if c.get("mapped", True) and c["class"]
                and not c["workspace"]["name"].startswith("special:") and c["workspace"]["name"] != "special"]
    except (ValueError, TypeError) as exc:
        raise IPCError("Invalid Hyprland client response; snapshot preserved") from exc


def workspace(client: dict) -> int | str:
    ws = client["workspace"]
    return ws["id"] if ws["id"] > 0 and ws["name"] == str(ws["id"]) else "name:" + ws["name"]


def entries(path: Path) -> list[dict]:
    value = json.loads(path.read_text())
    if not isinstance(value, list):
        raise SessionError("Snapshot must contain a list")
    for entry in value:
        if not isinstance(entry, dict) or not isinstance(entry.get("class"), str) or not entry["class"]:
            raise SessionError("Invalid snapshot application class")
        ws = entry.get("ws")
        if not ((isinstance(ws, int) and not isinstance(ws, bool) and ws > 0)
                or (isinstance(ws, str) and ws.startswith("name:") and len(ws) > 5
                    and not any(char in ws for char in ",\n\r\x00"))):
            raise SessionError("Invalid snapshot workspace")
        if not isinstance(entry.get("cmd"), str) or not shlex.split(entry["cmd"]):
            raise SessionError("Invalid snapshot launch command")
        for field in ("cwd", "exe", "instance", "folder"):
            if field in entry and not isinstance(entry[field], str):
                raise SessionError("Invalid snapshot " + field)
        terminal_cmd = entry.get("terminal_cmd")
        if terminal_cmd is not None:
            if (not isinstance(terminal_cmd, list) or not terminal_cmd
                    or not all(isinstance(arg, str) and arg for arg in terminal_cmd)
                    or Path(terminal_cmd[0]).name not in TERMINAL_COMMANDS):
                raise SessionError("Invalid snapshot terminal command")
    return value


def migrate() -> None:
    old = Path.home() / ".config/hypr/session.json"
    if not SNAPSHOT.exists() and old.is_file():
        saved = entries(old)
        if saved:
            atomic(SNAPSHOT, saved)
            report("Imported legacy session snapshot")


def process(pid: int) -> tuple[list[str], str, str]:
    root = Path("/proc") / str(pid)
    try:
        argv = [part.decode() for part in (root / "cmdline").read_bytes().split(b"\0") if part]
        exe = os.readlink(root / "exe")
        cwd = os.readlink(root / "cwd")
    except (OSError, UnicodeError) as exc:
        raise SessionError("Process metadata unavailable") from exc
    if not argv or not os.path.isfile(exe) or not os.access(exe, os.X_OK):
        raise SessionError("Process executable unavailable")
    # Electron overwrites argv[0] with a space-joined process title.
    if not shutil.which(argv[0]):
        argv = [exe]
    return argv, exe, cwd


def terminal(exe: str) -> bool:
    return Path(exe).name in {"kitty", "alacritty", "foot", "footclient", "wezterm", "wezterm-gui"}


def browser(cls: str) -> bool:
    return any(name in cls.lower() for name in ("zen", "firefox", "brave", "chromium", "google-chrome"))


def proc_stat(pid: int) -> tuple[int, int, int, int, int]:
    try:
        value = (Path("/proc") / str(pid) / "stat").read_text()
        fields = value[value.rfind(")") + 2:].split()
        return int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4]), int(fields[5])
    except (OSError, ValueError, IndexError) as exc:
        raise SessionError("Process status unavailable") from exc


def terminal_state(pid: int, fallback: str) -> tuple[str, list[str] | None]:
    """Return a terminal child's cwd and verified foreground interactive command."""
    try:
        children = (Path("/proc") / str(pid) / "task" / str(pid) / "children").read_text().split()
        for child in children:
            child_pid = int(child)
            child_root = Path("/proc") / child
            child_exe = os.readlink(child_root / "exe")
            child_name = Path(child_exe).name
            cwd = os.readlink(child_root / "cwd")
            _, child_pgrp, child_session, child_tty, foreground_pgrp = proc_stat(child_pid)
            if child_name in TERMINAL_COMMANDS:
                if child_tty == 0 or child_pgrp != child_pid or foreground_pgrp != child_pid:
                    return cwd, None
                argv, command_exe, _ = process(child_pid)
                if Path(command_exe).name not in TERMINAL_COMMANDS:
                    return cwd, None
                argv[0] = command_exe
                return cwd, argv
            if child_name not in {"bash", "zsh"}:
                continue
            if child_tty == 0 or foreground_pgrp <= 0 or foreground_pgrp == child_pgrp:
                return cwd, None
            command_pid = foreground_pgrp
            _, command_pgrp, command_session, command_tty, _ = proc_stat(command_pid)
            if command_pgrp != foreground_pgrp or command_session != child_session or command_tty != child_tty:
                return cwd, None
            argv, command_exe, _ = process(command_pid)
            if Path(command_exe).name not in TERMINAL_COMMANDS:
                return cwd, None
            argv[0] = command_exe
            return cwd, argv
    except (OSError, ValueError, SessionError):
        return fallback, None
    return fallback, None


def terminal_cwd(pid: int, fallback: str) -> str:
    return terminal_state(pid, fallback)[0]


def folders() -> dict[str, str]:
    found: dict[str, set[str]] = {}
    def walk(value: object) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if "folder" in key.lower() and isinstance(child, str) and child.startswith("file://"):
                    path = unquote(urlparse(child).path)
                    if Path(path).is_dir():
                        found.setdefault(Path(path).name, set()).add(path)
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    for path in (Path.home() / ".config").glob("Code*/User/globalStorage/storage.json"):
        try:
            walk(json.loads(path.read_text()))
        except (OSError, ValueError):
            report("Could not read editor folder metadata")
    return {name: next(iter(paths)) for name, paths in found.items() if len(paths) == 1}


def capture(current: list[dict]) -> list[dict]:
    saved = []
    code_folders = folders()
    for client in current:
        cls, pid = client["class"], client["pid"]
        try:
            argv, exe, cwd = process(pid)
            entry = {"ws": workspace(client), "class": cls, "exe": exe, "cwd": cwd}
            if terminal(exe):
                cwd, terminal_cmd = terminal_state(pid, cwd)
                # Preserve identity/config options, but never -e, shell jobs, sessions or old cwd flags.
                kept = []
                allowed = {"--class", "--name", "--app-id", "--config", "--config-file", "-c", "-o", "--override"}
                index = 1
                while index < len(argv):
                    arg = argv[index]
                    if arg in allowed and index + 1 < len(argv):
                        kept.extend(argv[index:index + 2])
                        index += 2
                    elif arg.split("=", 1)[0] in allowed and "=" in arg:
                        kept.append(arg)
                        index += 1
                    elif arg in {"--directory", "--working-directory", "--cwd", "--title", "-T", "--session"}:
                        index += 2
                    elif arg.startswith(("--directory=", "--working-directory=", "--cwd=", "--title=", "--session=")):
                        index += 1
                    else:
                        break
                name = Path(exe).name
                flag = "--cwd" if name.startswith("wezterm") else "--working-directory"
                argv = [exe] + (["start"] if name.startswith("wezterm") else []) + kept + [flag, cwd]
                entry["cwd"] = cwd
                if terminal_cmd is not None:
                    entry["terminal_cmd"] = terminal_cmd
            elif cls.lower() == "code" or "vscodium" in cls.lower():
                launcher = shutil.which("codium" if "vscodium" in cls.lower() else "code")
                if launcher:
                    argv[0] = launcher
                folder = next((code_folders[part.strip()] for part in client.get("title", "").split(" - ")
                               if part.strip() in code_folders), None)
                if folder:
                    entry["folder"] = folder
                    argv = [a for a in argv if a != "--new-window" and a != folder] + ["--new-window", folder]
            if browser(cls):
                entry["instance"] = str(pid)
                cleaned = [argv[0]]
                value_flags = {"--profile", "-profile", "-P", "--profile-directory", "--user-data-dir",
                               "--class", "--name", "--display", "--remote-debugging-port"}
                index = 1
                while index < len(argv):
                    arg = argv[index]
                    if arg in value_flags and index + 1 < len(argv):
                        cleaned.extend(argv[index:index + 2])
                        index += 2
                    else:
                        if arg.startswith("-") and arg not in {"--new-window", "--new-tab", "--url"}:
                            cleaned.append(arg)
                        index += 1
                if any(name in cls.lower() for name in ("brave", "chromium", "google-chrome")):
                    wrapper = Path.home() / ".local/bin/chromium-wrapper"
                    if wrapper.is_file() and os.access(wrapper, os.X_OK):
                        cleaned[0] = str(wrapper)
                    if "--restore-last-session" not in cleaned:
                        cleaned.append("--restore-last-session")
                argv = cleaned
            entry["cmd"] = shlex.join(argv)
            saved.append(entry)
        except SessionError as exc:
            raise SessionError(f"Cannot capture {cls}: {exc}; previous snapshot preserved") from exc
    return saved


def identities(current: list[dict]) -> set[tuple[str, int]]:
    return {(client["address"], client["pid"]) for client in current}


def checkpoint(
    quiet: bool, baseline: set[tuple[str, int]] | None = None, *,
    force: bool = False, freeze: bool = False, events: socket.socket | None = None,
) -> set[tuple[str, int]] | None:
    with locked("snapshot.lock"):
        # Freeze first, even if capture fails: teardown must retain the old target.
        if freeze:
            atomic(FROZEN, {"instance": INSTANCE})
        elif FROZEN.exists():
            if baseline is not None:
                return None
            raise SessionError("Checkpoints frozen for shutdown; use save --thaw to resume")
        migrate()
        pending = STATE / "restore-pending.json"
        if not freeze and (quiet or baseline is not None) and pending.exists():
            if baseline is not None:
                return None
            raise SessionError("Checkpoint blocked by incomplete restore; retry restore or explicitly save current windows")
        current = clients()
        observed = identities(current)
        if baseline is not None and observed == baseline and not force:
            return baseline
        saved = capture(current)
        # A disconnected event stream is not evidence of deliberate window closure.
        if events is not None:
            try:
                if events.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b"":
                    raise IPCError("Hyprland event socket disconnected; snapshot preserved")
            except BlockingIOError:
                pass
        if SNAPSHOT.exists():
            atomic(STATE / "session.backup.json", entries(SNAPSHOT))
        atomic(SNAPSHOT, saved)
        pending.unlink(missing_ok=True)
        if not quiet:
            report(f"Saved {len(saved)} windows")
        return observed


def browser_profile(argv: list[str]) -> dict[str, str]:
    identity = {}
    flags = {"--profile", "-profile", "-P", "--profile-directory", "--user-data-dir"}
    for index, arg in enumerate(argv[1:], 1):
        key, separator, value = arg.partition("=")
        if key in flags:
            identity[key] = value if separator else (argv[index + 1] if index + 1 < len(argv) else "")
    return identity


def matches(entry: dict, client: dict) -> bool:
    saved_class = entry["class"].casefold()
    if saved_class not in (client["class"].casefold(), client.get("initialClass", "").casefold()):
        return False
    try:
        argv, exe, cwd = process(client["pid"])
    except SessionError:
        return False
    if entry.get("exe") and exe != entry["exe"]:
        return False
    if terminal(exe):
        terminal_cwd, terminal_cmd = terminal_state(client["pid"], cwd)
        if entry.get("cwd") and entry["cwd"] != terminal_cwd:
            return False
        if entry.get("terminal_cmd") is not None and entry["terminal_cmd"] != terminal_cmd:
            return False
    if browser(entry["class"]) and browser_profile(shlex.split(entry["cmd"])) != browser_profile(argv):
        return False
    folder = entry.get("folder")
    return not folder or Path(folder).name in [part.strip() for part in client.get("title", "").split(" - ")]


def launch(entry: dict) -> None:
    argv = shlex.split(entry["cmd"])
    if not shutil.which(argv[0]):
        raise SessionError("Saved executable is missing")
    cwd = entry.get("cwd")
    if cwd and not Path(cwd).is_dir():
        raise SessionError("Saved working directory is missing")
    terminal_cmd = entry.get("terminal_cmd")
    if terminal_cmd is not None:
        argv.extend(terminal_cmd)
    command = "exec " + shlex.join(argv)
    if cwd:
        command = "cd -- " + shlex.quote(cwd) + " && " + command
    # One dispatcher argument; shell syntax and spaces are not split by hyprctl.
    hypr("eval", f"hl.exec_cmd({lua_string(command)})")


def restore() -> bool:
    with locked("snapshot.lock"):
        migrate()
        if not SNAPSHOT.exists():
            report("No saved session to restore")
            return True
        saved = entries(SNAPSHOT)
        if not saved:
            return True
        pending = STATE / "restore-pending.json"
        atomic(pending, {"instance": INSTANCE})
        used: set[str] = set()
        launched: set[tuple[str, str]] = set()
        failed = False
        current = clients()
        for entry in saved:
            cls = entry["class"]
            group = (cls, entry.get("instance", entry["cmd"]))
            try:
                candidates = [c for c in current if c["address"] not in used and matches(entry, c)]
                candidates.sort(key=lambda c: workspace(c) != entry["ws"])
                chosen = candidates[0] if candidates else None
                if chosen is None:
                    before = {c["address"] for c in current}
                    if not browser(cls) or group not in launched:
                        launch(entry)
                        launched.add(group)
                    deadline = time.monotonic() + WAIT_SECONDS
                    while time.monotonic() < deadline:
                        time.sleep(0.25)
                        current = clients()
                        candidates = [c for c in current if c["address"] not in used
                                      and c["address"] not in before and matches(entry, c)]
                        if candidates:
                            chosen = candidates[0]
                            break
                    if chosen is None:
                        raise SessionError("No matching window appeared; native session recovery may be disabled")
                if browser(cls):
                    launched.add(group)
                address = chosen["address"]
                if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                    raise SessionError("Invalid window address from compositor")
                used.add(address)
                if workspace(chosen) != entry["ws"]:
                    target = str(entry["ws"]) if isinstance(entry["ws"], int) else lua_string(entry["ws"])
                    hypr("dispatch", "hl.dsp.window.move({window=" + lua_string("address:" + address)
                         + ", workspace=" + target + ", follow=false})")
                current = clients()
            except SessionError as exc:
                failed = True
                report(f"Restore failed for {cls} on {entry['ws']}: {exc}")
                # Fail immediately on dead IPC rather than continuing to launch applications.
                current = clients()
        if not failed:
            pending.unlink(missing_ok=True)
            report(f"Restored or already satisfied {len(saved)} windows")
        else:
            report("Saved target retained; checkpoints paused until a successful restore")
        return not failed


def watch(restore_first: bool) -> None:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    path = runtime / "hypr" / SIGNATURE / ".socket2.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
        events.connect(str(path))
        events.setblocking(False)
        baseline = identities(clients())
        report("Session watcher connected to Hyprland event socket")
        if restore_first:
            try:
                restore()
            except (SessionError, OSError, ValueError) as exc:
                report(str(exc))
        buffer = b""
        # Startup discovery is only a baseline, never evidence of a count change.
        deadline: float | None = None
        force = False
        while True:
            timeout = None if deadline is None else max(0.0, deadline - time.monotonic())
            readable, _, _ = select.select([events], [], [], timeout)
            if readable:
                # Drain queued EOF before flushing a pending checkpoint. Bound both
                # incomplete records and a burst so an unhealthy stream fails safely.
                received = 0
                while True:
                    try:
                        chunk = events.recv(65536)
                    except BlockingIOError:
                        break
                    if not chunk:
                        raise IPCError("Hyprland event socket disconnected; snapshot preserved")
                    received += len(chunk)
                    buffer += chunk
                    if len(buffer) > EVENT_BUFFER_LIMIT or received > EVENT_BUFFER_LIMIT:
                        raise IPCError("Hyprland event stream exceeded buffer limit")
                    records = buffer.split(b"\n")
                    buffer = records.pop()
                    if any(record.partition(b">>")[0] in {b"openwindow", b"closewindow"} for record in records):
                        # Fixed window from the first event: bursts cannot postpone
                        # saving indefinitely. No deadline exists while idle.
                        if deadline is None:
                            deadline = time.monotonic() + DEBOUNCE_SECONDS
            if deadline is not None and time.monotonic() >= deadline:
                deadline = None
                try:
                    observed = checkpoint(True, baseline, force=force, events=events)
                    if observed is not None:
                        baseline = observed
                        force = False
                    else:
                        force = True
                except IPCError:
                    raise
                except (SessionError, OSError, ValueError) as exc:
                    report(str(exc))
                    # Retry on the next window event, never on a periodic timer.
                    force = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("save", "restore"))
    parser.add_argument("--quiet", action="store_true")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--watch", action="store_true")
    mode.add_argument("--watch-only", action="store_true")
    power = parser.add_mutually_exclusive_group()
    power.add_argument("--freeze", action="store_true", help="freeze watcher and save before shutdown")
    power.add_argument("--thaw", action="store_true", help="resume checkpoints after failed shutdown; do not save")
    args = parser.parse_args()
    if args.action == "save" and (args.watch or args.watch_only):
        parser.error("watch options are only valid for restore")
    if args.action != "save" and (args.freeze or args.thaw):
        parser.error("freeze/thaw options are only valid for save")
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    STATE.chmod(0o700)
    for name in ("session.json", "session.backup.json", "session.log", "restore-pending.json"):
        path = STATE / name
        if path.exists():
            path.chmod(0o600)
    try:
        if not SIGNATURE:
            raise SessionError("HYPRLAND_INSTANCE_SIGNATURE is required")
        if args.action == "save":
            if args.thaw:
                with locked("snapshot.lock"):
                    FROZEN.unlink(missing_ok=True)
                return 0
            return 0 if checkpoint(args.quiet, freeze=args.freeze) is not None else 1
        if not (args.watch or args.watch_only):
            clients()
            return 0 if restore() else 1
        with locked(f"compositor-{INSTANCE}.lock", blocking=False):
            watch(not args.watch_only)
    except (SessionError, OSError, ValueError) as exc:
        report(str(exc))
        return 1
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
