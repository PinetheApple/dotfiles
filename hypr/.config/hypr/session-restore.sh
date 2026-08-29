#!/usr/bin/env bash
# Replay ~/.config/hypr/session.json on login.
# For each saved window: launch its real command, wait for the new window to
# appear, then silently move it to the saved workspace. Sequential on purpose
# so each new window is unambiguous (dodges Hyprland's per-pid workspace rule
# failing on apps that delegate to an existing instance, e.g. VSCode).
set -uo pipefail
SESSION="$HOME/.config/hypr/session.json"
[ -f "$SESSION" ] || { echo "no session file: $SESSION"; exit 0; }

addrs() { hyprctl clients -j | python3 -c 'import json,sys;print("\n".join(c["address"] for c in json.load(sys.stdin)))'; }

mapfile -t LINES < <(python3 -c '
import json
for e in json.load(open("'"$SESSION"'")):
    print(f"{e[\"ws\"]}\t{e[\"cmd\"]}")
')

for line in "${LINES[@]}"; do
    ws="${line%%$'\t'*}"
    cmd="${line#*$'\t'}"
    echo "ws$ws  <-  $cmd"

    before="$(addrs)"
    hyprctl dispatch exec -- $cmd >/dev/null

    # wait up to ~12s for a brand-new window address
    new=""
    for _ in $(seq 1 60); do
        sleep 0.2
        after="$(addrs)"
        new="$(comm -13 <(echo "$before" | sort) <(echo "$after" | sort) | head -1)"
        [ -n "$new" ] && break
    done

    if [ -n "$new" ]; then
        hyprctl dispatch movetoworkspacesilent "$ws,address:$new" >/dev/null
    else
        echo "  ! no new window detected for: $cmd (left on default workspace)"
    fi
    sleep 0.4   # let the app settle before launching the next
done
