#!/usr/bin/env bash
# Restore once; --watch then checkpoints, --watch-only never launches apps.
set -euo pipefail
exec /usr/bin/python3 "$(dirname -- "$(readlink -f -- "$0")")/session.py" restore "$@"
