#!/bin/sh
# Touched by Claude Code hooks to record session activity.
date +%s > /tmp/claudekeep.heartbeat
# Trigger watchdog immediately so keepawake activates without waiting for the
# next scheduled run (StartInterval doesn't fire during system sleep).
/Users/jaychun/dev/personal/dotfiles/claudekeep/watchdog.sh </dev/null >/dev/null 2>&1 &
