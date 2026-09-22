#!/usr/bin/env bash
# Usage: power-confirm.sh poweroff | reboot
set -uo pipefail

action="${1:-poweroff}"
case "$action" in
    poweroff) verb="Shut down" ;;
    reboot)   verb="Reboot" ;;
    *) echo "usage: $0 poweroff|reboot"; exit 2 ;;
esac

HRMS="$HOME/.local/bin/hrms-checkin"
SAVE="$HOME/.config/hypr/session-save.sh"

checked_in() {
    "$HRMS" status 2>/dev/null | grep -qE '^Attendance:[[:space:]]+CLOCKED_IN$'
}

ask() {
    if command -v kdialog >/dev/null; then
        kdialog --title HRMS --yesno "$1"
    else
        zenity --question --title=HRMS --text="$1"
    fi
}

if checked_in && ask "You're clocked in to HRMS. Check out before $verb?"; then
    "$HRMS" checkout >>"$HOME/.local/state/hrms-checkin/hrms-checkin.log" 2>&1 || \
        notify-send --app-name=HRMS "HRMS checkout failed" "See hrms-checkin.log — continuing with $verb."
fi

if ! "$SAVE" --quiet --freeze; then
    notify-send --app-name="Hyprland session" "Session checkpoint failed" \
        "Keeping the previous checkpoint. See ~/.local/state/hypr-session/session.log — continuing with $verb."
fi

if systemctl "$action"; then
    exit 0
else
    status=$?
    if ! "$SAVE" --quiet --thaw; then
        notify-send --app-name="Hyprland session" "Session checkpoints remain frozen" \
            "Run ~/.config/hypr/session-save.sh --thaw to resume checkpoints."
    fi
    exit "$status"
fi
