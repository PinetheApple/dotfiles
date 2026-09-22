#!/bin/bash

set -u

config_dir="$HOME/.config/hypr"
config_file="$config_dir/hyprpaper.conf"
wallpaper_dir="$HOME/Pictures/Wallpapers"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hyprpaper"
log_file="$state_dir/startup.log"
hyprctl_bin="${HYPRCTL_BIN:-hyprctl}"
hyprpaper_bin="${HYPRPAPER_BIN:-hyprpaper}"
selector="${HYPRPAPER_SELECTOR:-$config_dir/hyprpaper.py}"
startup_timeout="${HYPRPAPER_STARTUP_TIMEOUT_SECONDS:-${HYPRPAPER_READY_TIMEOUT_SECONDS:-10}}"
poll_interval="${HYPRPAPER_POLL_INTERVAL_SECONDS:-0.1}"

if ! mkdir -p "$state_dir"; then
    printf 'hyprpaper: unable to create startup log directory: %s\n' "$state_dir" >&2
    exit 1
fi

log_failure() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >>"$log_file"
}

if [[ ! -d "$wallpaper_dir" ]]; then
    log_failure "wallpaper directory does not exist: $wallpaper_dir"
    exit 1
fi

if ! config_tmp=$(mktemp "${config_file}.tmp.XXXXXX"); then
    log_failure "unable to create temporary wallpaper config beside $config_file"
    exit 1
fi
trap 'rm -f -- "${config_tmp:-}"' EXIT

images=()
while IFS= read -r -d '' image; do
    images+=("$image")
done < <(find "$wallpaper_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 2>>"$log_file")

if ((${#images[@]} == 0)); then
    log_failure "no wallpaper images found in $wallpaper_dir"
    exit 1
fi

{
    for image in "${images[@]}"; do
        printf 'preload = %s\n' "$image"
    done
    printf '\nwallpaper = ,%s\n\nsplash = false\n' "${images[0]}"
} >"$config_tmp" || {
    log_failure "unable to write temporary wallpaper config: $config_tmp"
    exit 1
}

if ! mv -f -- "$config_tmp" "$config_file"; then
    log_failure "unable to install wallpaper config: $config_file"
    exit 1
fi
config_tmp=""
trap - EXIT

runtime_dir="${XDG_RUNTIME_DIR:-}"
instance_signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [[ -z "$runtime_dir" || -z "$instance_signature" ]]; then
    log_failure "missing XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE"
    exit 1
fi

if ! [[ "$startup_timeout" =~ ^[0-9]+$ ]]; then
    startup_timeout=10
fi
socket_path="$runtime_dir/hypr/$instance_signature/.hyprpaper.sock"

monitors_ready() {
    local monitors
    monitors=$("$hyprctl_bin" monitors -j 2>/dev/null) || return 1
    monitors="${monitors//[[:space:]]/}"
    [[ "$monitors" == \[* && "$monitors" == *\{* && "$monitors" == *\}* && "$monitors" == *\] ]]
}

daemon_pid=""
if [[ -S "$socket_path" ]]; then
    :
else
    "$hyprpaper_bin" --config "$config_file" >>"$log_file" 2>&1 &
    daemon_pid=$!
fi

ready=false
deadline=$((SECONDS + startup_timeout))
while ((SECONDS <= deadline)); do
    if [[ -S "$socket_path" ]] && monitors_ready; then
        ready=true
        break
    fi
    sleep "$poll_interval"
done

if [[ "$ready" != true ]]; then
    log_failure "hyprpaper readiness timed out after ${startup_timeout}s (socket=$socket_path)"
    if [[ -n "$daemon_pid" ]]; then
        kill "$daemon_pid" 2>/dev/null || true
        wait "$daemon_pid" 2>/dev/null || true
    fi
    exit 1
fi

selector_status=0
if [[ ! -x "$selector" ]]; then
    log_failure "wallpaper selector is not executable: $selector"
    selector_status=1
else
    "$selector" >>"$log_file" 2>&1 || selector_status=$?
    if ((selector_status != 0)); then
        log_failure "wallpaper selector failed with status $selector_status"
    fi
fi

daemon_status=0
if [[ -n "$daemon_pid" ]]; then
    wait "$daemon_pid" || daemon_status=$?
    if ((daemon_status != 0)); then
        log_failure "hyprpaper exited with status $daemon_status"
    fi
fi

if ((selector_status != 0 || daemon_status != 0)); then
    exit 1
fi
