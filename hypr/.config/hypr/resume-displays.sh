#!/usr/bin/env bash
# Restore monitor scanout after DPMS or system resume.
set -u

readonly LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr-resume-displays.lock"
readonly NVIDIA_HOLD=/run/nvidia-dgpu-rpm/external-before-sleep
readonly DPMS_ENABLE='hl.dsp.dpms({ action = "enable" })'

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

monitors_ready() {
    local require_hdmi=false
    [[ -e $NVIDIA_HOLD ]] && require_hdmi=true

    hyprctl monitors -j | python3 -c '
import json
import sys

require_hdmi = sys.argv[1] == "true"
monitors = json.load(sys.stdin)
ready = bool(monitors) and all(
    bool(monitor.get("dpmsStatus"))
    and not monitor.get("disabled", True)
    and monitor.get("width", 0) > 0
    and monitor.get("height", 0) > 0
    for monitor in monitors
)
if require_hdmi:
    ready = ready and any(monitor.get("name") == "HDMI-A-1" for monitor in monitors)
raise SystemExit(0 if ready else 1)
' "$require_hdmi"
}

for delay in 0 1 2 3 4; do
    ((delay > 0)) && sleep "$delay"
    hyprctl dispatch "$DPMS_ENABLE" >/dev/null 2>&1 || continue
    sleep 1
    monitors_ready && exit 0
done

printf '%s\n' 'display recovery did not restore every expected monitor' \
    | systemd-cat -t hypr-resume-displays -p warning
exit 1
