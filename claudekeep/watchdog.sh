#!/bin/sh
# Runs on a schedule. If the heartbeat is fresh, keep the machine awake.
# Otherwise, release everything.

HEARTBEAT=/tmp/claudekeep.heartbeat
PIDFILE=/tmp/claudekeep.caffeinate.pid
LOG=/tmp/claudekeep.log
TIMEOUT=3600  # 1 hour

log() { echo "[$(date -u +%FT%TZ)] $*" >> "$LOG"; }

is_active() {
    [ -f "$HEARTBEAT" ] || return 1
    last=$(cat "$HEARTBEAT" 2>/dev/null)
    [ -n "$last" ] || return 1
    now=$(date +%s)
    [ $((now - last)) -lt $TIMEOUT ]
}

start_keepawake() {
    # caffeinate handles idle sleep. Spawn it only if not already running.
    if ! { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }; then
        caffeinate -ims </dev/null >/dev/null 2>&1 &
        echo $! > "$PIDFILE"
        log "keepawake ON (caffeinate pid $(cat $PIDFILE))"
    fi
    # disablesleep blocks lid-close (clamshell) sleep, which caffeinate cannot.
    # macOS resets it on power-source changes, so re-assert it every run even
    # when caffeinate is already alive.
    if [ "$(pmset -g | awk '/SleepDisabled/{print $2}')" != "1" ]; then
        sudo -n pmset -a disablesleep 1 >/dev/null 2>&1
        log "disablesleep re-asserted"
    fi
}

stop_keepawake() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
    sudo -n pmset -a disablesleep 0 >/dev/null 2>&1
    log "keepawake OFF"
}

if is_active; then
    start_keepawake
else
    if [ -f "$PIDFILE" ]; then
        stop_keepawake
    fi
fi
