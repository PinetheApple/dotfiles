#!/usr/bin/env bash
# Save current windows, including []; --quiet suppresses success output.
# --freeze checkpoints and pauses autosaves for shutdown; --thaw resumes without saving.
set -euo pipefail
exec /usr/bin/python3 "$(dirname -- "$(readlink -f -- "$0")")/session.py" save "$@"
