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

[ -x "$SAVE" ] && "$SAVE" >/dev/null 2>&1

systemctl "$action"
