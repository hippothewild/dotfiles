#!/bin/sh
# Runs on a schedule. If the heartbeat is fresh, keep the machine awake.
# Otherwise, release everything.

HEARTBEAT=/tmp/claudekeep.heartbeat
PIDFILE=/tmp/claudekeep.caffeinate.pid
LOCK=/tmp/claudekeep.lock.d
LOG=/tmp/claudekeep.log
TIMEOUT=3600  # 1 hour
LOG_MAX=1048576  # 1 MB

log() { echo "[$(date -u +%FT%TZ)] $*" >> "$LOG"; }

# One watchdog at a time. Concurrent runs raced on PIDFILE and each spawned its
# own caffeinate, leaking dozens. A lock older than a minute is stale.
if ! mkdir "$LOCK" 2>/dev/null; then
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ] || exit 0
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt "$LOG_MAX" ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
fi

is_active() {
    [ -f "$HEARTBEAT" ] || return 1
    last=$(cat "$HEARTBEAT" 2>/dev/null)
    [ -n "$last" ] || return 1
    now=$(date +%s)
    [ $((now - last)) -lt $TIMEOUT ]
}

caffeinate_alive() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

start_keepawake() {
    # caffeinate handles idle sleep. Spawn it only if not already running.
    # -t makes it expire on its own, so a lost PIDFILE can't leak it forever.
    if ! caffeinate_alive; then
        caffeinate -ims -t $((TIMEOUT + 300)) </dev/null >/dev/null 2>&1 &
        echo $! > "$PIDFILE"
        log "keepawake ON (caffeinate pid $!)"
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
