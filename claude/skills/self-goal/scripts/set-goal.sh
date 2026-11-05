#!/usr/bin/env bash
# Inject "/goal <condition>" into this Claude session's own terminal pane.
# /goal typed mid-turn is applied within the running turn (verified 2.1.302),
# so the goal is active before the calling turn tries to stop.
# Claude Code has no way to set a goal on a running session from outside its
# prompt, so each terminal needs its own way of typing into the pane.
set -euo pipefail

# tmux first: it is the innermost layer when nested, and its panes inherit the
# outer terminal's variables, which would target whichever pane has focus.
if [[ -n "${TMUX_PANE:-}" ]]; then
  send_text() {
    # tmux reads a trailing ";" in an argument as a command separator.
    local text="$1"
    [[ "$text" != *\; ]] || text="${text%;}\\;"
    tmux send-keys -t "$TMUX_PANE" -l "$text"
  }
  send_enter() { tmux send-keys -t "$TMUX_PANE" Enter; }
elif [[ -n "${CMUX_SURFACE_ID:-}" ]]; then
  send_text() { cmux send --surface "$CMUX_SURFACE_ID" "$1"; }
  send_enter() { cmux send-key --surface "$CMUX_SURFACE_ID" Enter; }
elif [[ -n "${REX_BLOCK:-}" && -n "${REX_SESSION:-}" && -n "${REX_SERVER:-}" ]]; then
  # rex ignores REX_SERVER unless it is passed with -S.
  send_text() { rex -S "$REX_SERVER" send -s "$REX_SESSION" -b "$REX_BLOCK" "$1"; }
  send_enter() { rex -S "$REX_SERVER" send-key -s "$REX_SESSION" -b "$REX_BLOCK" enter; }
elif [[ -n "${WEZTERM_PANE:-}" ]]; then
  # --no-paste types the text; a bracketed paste may not read as a slash command.
  send_text() { wezterm cli send-text --pane-id "$WEZTERM_PANE" --no-paste "$1"; }
  send_enter() { wezterm cli send-text --pane-id "$WEZTERM_PANE" --no-paste $'\r'; }
else
  echo "set-goal: unsupported terminal (supported: cmux, Rex, WezTerm, tmux)" >&2
  exit 1
fi

cond="$*"
[[ -n "$cond" ]] || { echo "usage: set-goal.sh <condition>" >&2; exit 2; }
# Newlines/ESC would let one call smuggle extra lines or keystrokes.
[[ "$cond" != *[[:cntrl:]]* ]] || { echo "set-goal: control characters rejected" >&2; exit 2; }
(( ${#cond} <= 500 )) || { echo "set-goal: condition longer than 500 chars" >&2; exit 2; }
[[ "$cond" != clear && "$cond" != clear\ * ]] || { echo "set-goal: refusing to clear the goal" >&2; exit 2; }

send_text "/goal $cond" >/dev/null
# TUIs can treat text+Enter in one burst as a paste and not submit it.
sleep 0.3
send_enter >/dev/null
echo "queued: /goal $cond"
