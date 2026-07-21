#!/usr/bin/env bash
# Snapshot current Hyprland windows -> ~/.config/hypr/session.json
# Run via keybind (SUPER+SHIFT+S) whenever you want to remember the layout.
#
# Base launch command comes from the process's real /proc/PID/cmdline, so the
# exact executable path + flags are preserved. Two unavoidable augmentations:
#   - editors/terminals: cmdline lacks the open folder / cwd, so we add it.
#   - browsers: one process serves all windows; we launch once and rely on the
#     browser's own "restore tabs" setting.
set -euo pipefail
OUT="$HOME/.config/hypr/session.json"

python3 - "$OUT" <<'PY'
import json, os, sys, subprocess, glob, shlex

out = sys.argv[1]
clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))

# --- map open VSCode folders: basename -> full path (from VSCode storage) ---
code_folders = {}
for sf in glob.glob(os.path.expanduser("~/.config/Code*/User/globalStorage/storage.json")):
    try:
        data = json.load(open(sf))
    except Exception:
        continue
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if "folder" in k.lower() and isinstance(v, str) and v.startswith("file://"):
                    p = v[7:]
                    code_folders.setdefault(os.path.basename(p), p)
                walk(v)
        elif isinstance(o, list):
            for i in o: walk(i)
    walk(data)

def cmdline(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\x00")
        return [a.decode() for a in raw if a]
    except Exception:
        return []

def descendants(pid):
    seen, stack = [], [pid]
    while stack:
        p = stack.pop()
        for tf in glob.glob(f"/proc/{p}/task/*/children"):
            try:
                for c in open(tf).read().split():
                    seen.append(int(c)); stack.append(int(c))
            except Exception:
                pass
    return seen

def cwd_of(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except Exception:
        return None

def term_cwd(pid):
    home = os.path.expanduser("~")
    cands = [c for c in (cwd_of(d) for d in descendants(pid)) if c]
    for c in cands:
        if c != home:
            return c
    return (cands[0] if cands else cwd_of(pid)) or home

def code_folder(title):
    for seg in [s.strip() for s in title.split(" - ")]:
        if seg in code_folders:
            return code_folders[seg]
    return None

entries, seen_browser = [], set()
for c in clients:
    ws = c["workspace"]["id"]
    if ws < 0:                       # special / scratchpad workspaces
        continue
    cls = c["class"]; pid = c["pid"]; title = c.get("title", "")
    cl = cls.lower()
    argv = cmdline(pid)
    # some apps (e.g. VSCode) rewrite their argv into one space-joined blob;
    # recover the real binary as the first whitespace token of argv[0].
    exe = argv[0].split()[0] if argv else cls

    if "zen" in cl or "brave" in cl or "chromium" in cl or "firefox" in cl:
        # one process serves every window; launch the real binary once,
        # the browser restores its own tabs/windows.
        if pid in seen_browser:
            continue
        seen_browser.add(pid)
        cmd = shlex.join(argv) if argv else exe
    elif cl == "code" or cl.endswith("-code") or "vscodium" in cl:
        f = code_folder(title)
        cmd = f"{exe} --new-window {shlex.quote(f)}" if f else shlex.join(argv)
    elif cl in ("kitty", "alacritty", "foot", "wezterm", "kitty-2"):
        cwd = term_cwd(pid)
        # honour the real cmdline, just inject the directory flag
        flag = {"kitty": "--working-directory", "alacritty": "--working-directory",
                "foot": "--working-directory", "wezterm": "--cwd"}.get(cl, None)
        if flag and flag not in argv:
            cmd = shlex.join(argv + [flag, cwd])
        else:
            cmd = shlex.join(argv)
    else:
        # everything else: replay its real launch command verbatim
        cmd = shlex.join(argv) if argv else cls

    entries.append({"ws": ws, "class": cls, "cmd": cmd})

entries.sort(key=lambda e: e["ws"])
json.dump(entries, open(out, "w"), indent=2)
print(f"saved {len(entries)} windows -> {out}")
for e in entries:
    print(f'  ws{e["ws"]:<3} {e["cmd"]}')
PY

command -v notify-send >/dev/null && notify-send "Hyprland session saved" "$(grep -c '"ws"' "$OUT") windows" || true
