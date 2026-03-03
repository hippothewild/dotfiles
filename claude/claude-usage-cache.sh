#!/bin/bash
# Fetches Claude Code usage data from OAuth API with file-based caching.
# Called by WezTerm status bar. Caches for 60 seconds to avoid excessive API calls.

CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_MAX_AGE=60

# Return cache if still fresh
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
  if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Extract OAuth token from macOS Keychain
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo '{}'
  exit 1
fi

# Fetch and cache
result=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

if [ -n "$result" ] && echo "$result" | jq -e '.five_hour' >/dev/null 2>&1; then
  echo "$result" > "$CACHE_FILE"
  echo "$result"
else
  # Return stale cache if fetch failed
  [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE" || echo '{}'
fi
