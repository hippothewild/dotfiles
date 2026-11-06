#!/bin/sh
# Touched by Claude Code hooks to record session activity.
# Runs on every PostToolUse/UserPromptSubmit across all sessions, so keep it cheap.
HEARTBEAT=/tmp/claudekeep.heartbeat
PIDFILE=/tmp/claudekeep.caffeinate.pid

# Write via temp + mv: a plain `>` truncates first, and a watchdog reading in
# that window saw an empty file and wrongly released keepawake.
tmp="$HEARTBEAT.$$"
date +%s > "$tmp" && mv -f "$tmp" "$HEARTBEAT"

# Keepawake already running -> nothing to do; the scheduled watchdog (every
# 300s) handles the timeout. Only kick the watchdog when it needs to start.
# (read/kill are builtins, so the common path forks nothing extra.)
if [ -f "$PIDFILE" ] && read -r pid < "$PIDFILE" && kill -0 "$pid" 2>/dev/null; then
    exit 0
fi
/Users/jaychun/dev/personal/dotfiles/claudekeep/watchdog.sh </dev/null >/dev/null 2>&1 &
