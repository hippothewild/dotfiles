#!/usr/bin/env bash
# Inject "/goal <condition>" into this Claude session's own cmux surface.
# /goal typed mid-turn is applied within the running turn (verified 2.1.302),
# so the goal is active before the calling turn tries to stop.
set -euo pipefail

cond="$*"
[[ -n "${CMUX_SURFACE_ID:-}" ]] || { echo "set-goal: not inside a cmux surface" >&2; exit 1; }
[[ -n "$cond" ]] || { echo "usage: set-goal.sh <condition>" >&2; exit 2; }
# Newlines/ESC would let one call smuggle extra lines or keystrokes.
[[ "$cond" != *[[:cntrl:]]* ]] || { echo "set-goal: control characters rejected" >&2; exit 2; }
(( ${#cond} <= 500 )) || { echo "set-goal: condition longer than 500 chars" >&2; exit 2; }
[[ "$cond" != clear && "$cond" != clear\ * ]] || { echo "set-goal: refusing to clear the goal" >&2; exit 2; }

cmux send --surface "$CMUX_SURFACE_ID" "/goal $cond" >/dev/null
# TUIs can treat text+Enter in one burst as a paste and not submit it.
sleep 0.3
cmux send-key --surface "$CMUX_SURFACE_ID" Enter >/dev/null
echo "queued: /goal $cond"
