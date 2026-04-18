#!/bin/bash

set -u

input=$(cat)

# Pass-through for WezTerm status bar consumers
echo "$input" > /tmp/claude-code-session.json 2>/dev/null

# Parse all stdin fields in a single jq call. `read` collapses consecutive
# whitespace in IFS, so we use \x1f (unit separator) to keep empty fields
# distinct. Rate-limit and context fields were added by Claude Code v2.1.6+ —
# when present they let us skip the OAuth usage endpoint and transcript
# parsing entirely.
IFS=$'\x1f' read -r \
  cwd model output_style agent vim_mode transcript_path \
  ctx_pct \
  s_util s_reset_epoch w_util w_reset_epoch \
  _ < <(
  echo "$input" | jq -j '
    [
      (.workspace.current_dir // .cwd // ""),
      (.model.display_name // ""),
      (.output_style.name // ""),
      (.agent.name // ""),
      (.vim.mode // ""),
      (.transcript_path // ""),
      (.context_window.used_percentage // ""),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.seven_day.resets_at // ""),
      "."
    ] | join("\u001f")'
)

# Colors (256-color). DIM is readable on dark terminals unlike bright-black (90).
C_RESET=$'\033[0m'
C_PATH=$'\033[33m'
C_GIT=$'\033[34m'
C_ACCENT=$'\033[36m'          # cyan — costs, primary values
C_LABEL=$'\033[38;5;252m'     # near-white — row labels
C_DIM=$'\033[38;5;244m'       # medium gray — secondary info (visible on dark)
C_MUTED=$'\033[38;5;240m'     # darker gray — empty progress dots
C_GREEN=$'\033[38;5;114m'     # pastel sage green — weekly bar (and low util fallback)
C_YELLOW=$'\033[38;5;222m'    # pastel cream/mustard — session bar (and medium util fallback)
C_RED=$'\033[38;5;210m'       # pastel coral — high utilization
C_MAGENTA=$'\033[35m'         # agent indicator
C_BOLD_WHITE=$'\033[1;38;5;255m'  # bright white + bold — model name
C_BLUE=$'\033[38;5;111m'          # pastel sky blue — context indicator

CACHE_DIR="${TMPDIR:-/tmp}"
LIMITS_CACHE="$CACHE_DIR/claude-limits-cache.json"
DAILY_CACHE="$CACHE_DIR/claude-daily-cache.json"
LIMITS_TTL=120    # 2 min — rate-limit data changes fast while working
DAILY_TTL=300     # 5 min — daily aggregates change slowly

shorten_path() {
  local path="$1"
  path="${path/#$HOME/~}"
  if [ ${#path} -gt 40 ]; then
    IFS='/' read -ra parts <<< "$path"
    local result="" last_idx=$((${#parts[@]} - 1))
    for i in "${!parts[@]}"; do
      if [ $i -eq 0 ] || [ $i -eq $last_idx ]; then
        result="${result:+$result/}${parts[$i]}"
      else
        result="$result/${parts[$i]:0:1}"
      fi
    done
    echo "$result"
  else
    echo "$path"
  fi
}

get_git_info() {
  git rev-parse --git-dir >/dev/null 2>&1 || return
  local branch dirty=""
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [ -z "$branch" ] && return
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    dirty="*"
  fi
  printf " %s(%s%s)%s" "$C_GIT" "$branch" "$dirty" "$C_RESET"
}

is_stale() {
  local file="$1" ttl="$2"
  [ ! -f "$file" ] && return 0
  local mtime now
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  now=$(date +%s)
  [ $((now - mtime)) -gt "$ttl" ]
}

# mkdir-based non-blocking lock (portable on macOS, unlike flock).
# Usage: acquire_lock /path/to/lockdir || return 0
acquire_lock() {
  mkdir "$1" 2>/dev/null
}
release_lock() {
  rmdir "$1" 2>/dev/null
}

refresh_limits() {
  local lock="$LIMITS_CACHE.lock.d"
  acquire_lock "$lock" || return 0

  local creds token plan resp
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$creds" ]; then
    token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
    plan=$(echo "$creds" | jq -r '.claudeAiOauth.subscriptionType // empty')
    if [ -n "$token" ]; then
      resp=$(curl -s --max-time 5 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20")
      if [ -n "$resp" ]; then
        echo "$resp" | jq --arg plan "$plan" --arg ts "$(date +%s)" '{
          session: .five_hour,
          weekly: .seven_day,
          sonnet: .seven_day_sonnet,
          plan: $plan,
          fetched_at: ($ts | tonumber)
        }' > "$LIMITS_CACHE.tmp" 2>/dev/null && mv "$LIMITS_CACHE.tmp" "$LIMITS_CACHE"
      fi
    fi
  fi

  release_lock "$lock"
}

refresh_daily() {
  local lock="$DAILY_CACHE.lock.d"
  acquire_lock "$lock" || return 0

  local json
  json=$(bunx ccusage@latest daily --json 2>/dev/null)
  if [ -n "$json" ]; then
    echo "$json" > "$DAILY_CACHE.tmp" && mv "$DAILY_CACHE.tmp" "$DAILY_CACHE"
  fi

  release_lock "$lock"
}

# Only refresh the OAuth usage cache when stdin didn't deliver rate_limits —
# v2.1.6+ carries the values directly, so the cache is dead weight on modern
# clients. `refresh_daily` (ccusage) always runs: stdin carries no daily totals.
if [ -z "$s_util" ] && [ -z "$w_util" ] && is_stale "$LIMITS_CACHE" "$LIMITS_TTL"; then
  (refresh_limits >/dev/null 2>&1 &) >/dev/null 2>&1
fi
if is_stale "$DAILY_CACHE" "$DAILY_TTL"; then
  (refresh_daily >/dev/null 2>&1 &) >/dev/null 2>&1
fi

# Format "resets in Nd Nh" / "Nh Nm" / "Nm". Input can be either:
#   - ISO-8601 string like "2026-04-18T06:00:00.432+00:00" (OAuth cache path)
#   - Epoch seconds integer (stdin .rate_limits path)
fmt_reset() {
  local v="$1"
  [ -z "$v" ] || [ "$v" = "null" ] && { echo ""; return; }
  local ts now diff d h m
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    ts="$v"
  else
    # API returns UTC timestamps; strip fractional + offset and parse as UTC.
    local iso_trim="${v%%.*}"
    iso_trim="${iso_trim%%+*}"
    iso_trim="${iso_trim%Z}"
    ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso_trim" +%s 2>/dev/null) || { echo ""; return; }
  fi
  now=$(date +%s)
  diff=$((ts - now))
  [ $diff -le 0 ] && { echo "<1m"; return; }
  d=$((diff / 86400))
  h=$(((diff % 86400) / 3600))
  m=$(((diff % 3600) / 60))
  if [ $d -gt 0 ]; then echo "${d}d ${h}h"
  elif [ $h -gt 0 ]; then echo "${h}h ${m}m"
  else echo "${m}m"; fi
}

# 10-dot progress bar. Arg 2 is the ANSI color sequence to use for filled dots.
progress_bar() {
  local pct="$1" color="$2"
  pct=${pct%.*}
  [ -z "$pct" ] && pct=0
  local filled=$((pct / 10))
  [ $filled -gt 10 ] && filled=10
  local out=""
  for ((i=0; i<10; i++)); do
    [ "$i" -gt 0 ] && out="$out "
    if [ "$i" -lt "$filled" ]; then
      out="${out}${color}●${C_RESET}"
    else
      out="${out}${C_MUTED}·${C_RESET}"
    fi
  done
  printf "%s" "$out"
}

# Pick ANSI color sequence for a utilization percentage.
util_color() {
  local pct="${1%.*}"
  [ -z "$pct" ] && pct=0
  if [ "$pct" -ge 80 ]; then printf "%s" "$C_RED"
  elif [ "$pct" -ge 50 ]; then printf "%s" "$C_YELLOW"
  else printf "%s" "$C_GREEN"; fi
}

# Shorten "Opus 4.7 (1M context)" → "Opus 4.7 (1M)". The full name is chatty
# on a one-line header; the "context" suffix is implied by the number.
short_model() {
  local m="$1"
  m="${m// (1M context)/ (1M)}"
  m="${m// (200k context)/ (200k)}"
  echo "$m"
}

# Compute context% when stdin didn't provide it (older Claude Code versions).
# Tail the last 256 lines of the transcript, take the last message.usage entry,
# and ratio against the model's window. Returns empty if unavailable.
context_pct_from_transcript() {
  local tp="$1" m="$2"
  [ -z "$tp" ] || [ ! -f "$tp" ] && return
  local window=200000
  [[ "$m" == *"1M"* ]] && window=1000000
  local tokens
  tokens=$(tail -n 256 "$tp" 2>/dev/null | jq -rs '
    map(select(.message.usage != null)) | last as $e
    | if $e == null then empty
      else ($e.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0))
      end
  ' 2>/dev/null)
  [ -z "$tokens" ] || [ "$tokens" = "0" ] && return
  awk -v t="$tokens" -v w="$window" 'BEGIN{ printf "%d", (t * 100 / w) + 0.5 }'
}

# Pick a color matching context utilization (thresholds match util_color).
ctx_color() {
  local pct="${1:-0}"
  if [ "$pct" -ge 80 ]; then printf "%s" "$C_RED"
  elif [ "$pct" -ge 50 ]; then printf "%s" "$C_YELLOW"
  else printf "%s" "$C_GREEN"; fi
}

# Line 1: model | ctx% | path (main*) + decorations
short_path=$(shorten_path "$cwd")
model_short=$(short_model "${model:-Claude}")
# Prefer stdin .context_window.used_percentage (Claude Code v2.1.6+); otherwise
# fall back to parsing the transcript.
if [ -n "$ctx_pct" ]; then
  ctx="$ctx_pct"
else
  ctx=$(context_pct_from_transcript "$transcript_path" "${model:-}")
fi
sep="${C_DIM}|${C_RESET}"

line1="${C_BOLD_WHITE}${model_short}${C_RESET}"
if [ -n "$ctx" ]; then
  line1="$line1 $sep ${C_BLUE}ctx ${ctx}%${C_RESET}"
fi
line1="$line1 $sep ${C_PATH}${short_path}${C_RESET}$(get_git_info)"
[ -n "$agent" ] && line1="$line1 ${C_MAGENTA}[agent:$agent]${C_RESET}"
[ -n "$vim_mode" ] && line1="$line1 ${C_ACCENT}[$vim_mode]${C_RESET}"
[ -n "$output_style" ] && [ "$output_style" != "default" ] && line1="$line1 ${C_GREEN}[$output_style]${C_RESET}"

# Render the session/weekly rate-limit rows. Data source is resolved upstream
# (stdin .rate_limits > cached OAuth response). Each argument may be empty.
#
# Args: s_util s_reset w_util w_reset
#   s_reset/w_reset can be an ISO-8601 timestamp OR an epoch seconds integer;
#   fmt_reset handles both.
build_limits_block() {
  local su="$1" sr="$2" wu="$3" wr="$4"
  [ -z "$su$wu" ] && return

  local rows=""
  _render_row() {
    local util="$1" resets="$2" label="$3" base_color="$4"
    [ -z "$util" ] && return
    local pct_int color bar left reset_str line
    pct_int=${util%.*}
    if [ "$pct_int" -ge 80 ]; then color="$C_RED"; else color="$base_color"; fi
    bar=$(progress_bar "$util" "$color")
    left=$(printf "%.0f" "$util")
    reset_str=$(fmt_reset "$resets")
    line=$(printf "  %s%s%s %s %s%3s%%%s" \
      "$C_DIM" "$label" "$C_RESET" "$bar" "$color" "$left" "$C_RESET")
    [ -n "$reset_str" ] && line="$line ${C_DIM}| Resets in $reset_str${C_RESET}"
    rows="${rows}${line}"$'\n'
  }
  _render_row "$su" "$sr" "Session" "$C_YELLOW"
  _render_row "$wu" "$wr" "Weekly " "$C_GREEN"
  printf "%s" "$rows"
}

# Read rate-limit values from the cached OAuth response. Used as fallback when
# stdin doesn't carry .rate_limits (older Claude Code versions).
read_limits_cache() {
  [ ! -f "$LIMITS_CACHE" ] && return
  jq -j '
    [
      (.session.utilization // ""),
      (.session.resets_at   // ""),
      (.weekly.utilization  // ""),
      (.weekly.resets_at    // ""),
      "."
    ] | join("\u001f")' "$LIMITS_CACHE" 2>/dev/null
}

# Line 6+: daily summary (today / last 7d)
# Token split used across all rows:
#   cache  = cacheReadTokens              (reused from prompt cache)
#   input  = inputTokens + cacheCreationTokens  (new input that hit the model)
#   output = outputTokens
# Display: "$593.25 | 698.3M tok (658.0M/39.6M/617.5K)"
build_daily_block() {
  [ ! -f "$DAILY_CACHE" ] && return

  # Single jq: today's totals + last-7d aggregates in one 8-field record.
  local t_cost t_cache t_in t_out w_cost w_cache w_in w_out _
  IFS=$'\x1f' read -r t_cost t_cache t_in t_out w_cost w_cache w_in w_out _ < <(
    jq -j '
      (.daily[-1] // null) as $today
      | (.daily[-7:]) as $week
      | [
          ($today.totalCost // 0),
          ($today.cacheReadTokens // 0),
          (($today.inputTokens // 0) + ($today.cacheCreationTokens // 0)),
          ($today.outputTokens // 0),
          ([$week[] | .totalCost]           | add // 0),
          ([$week[] | .cacheReadTokens]     | add // 0),
          ([$week[] | ((.inputTokens // 0) + (.cacheCreationTokens // 0))] | add // 0),
          ([$week[] | .outputTokens]        | add // 0),
          "."
        ] | map(tostring) | join("\u001f")
    ' "$DAILY_CACHE" 2>/dev/null
  )

  _render_daily_row() {
    local label="$1" cost="$2" cache_t="$3" in_t="$4" out_t="$5"
    [ -z "$cost" ] && return
    local total_t cost_str
    total_t=$((cache_t + in_t + out_t))
    cost_str=$(printf "\$%.2f" "$cost")
    printf "  %s%-10s%s%s%22s%s %s| %s tok (%s/%s/%s)%s\n" \
      "$C_DIM" "$label" "$C_RESET" \
      "$C_LABEL" "$cost_str" "$C_RESET" \
      "$C_DIM" "$(human_num "$total_t")" \
      "$(human_num "$cache_t")" "$(human_num "$in_t")" "$(human_num "$out_t")" \
      "$C_RESET"
  }
  _render_daily_row "Today"   "$t_cost" "$t_cache" "$t_in" "$t_out"
  _render_daily_row "Last 7d" "$w_cost" "$w_cache" "$w_in" "$w_out"
}

human_num() {
  local n="$1"
  [ -z "$n" ] && { echo "0"; return; }
  # Pure-bash: avoid forking awk per call. printf handles one-decimal rounding.
  if   [ "$n" -ge 1000000000 ]; then printf "%.1fB" "$(( (n * 10 + 500000000) / 1000000000 ))e-1"
  elif [ "$n" -ge 1000000    ]; then printf "%.1fM" "$(( (n * 10 + 500000)    / 1000000    ))e-1"
  elif [ "$n" -ge 1000       ]; then printf "%.1fK" "$(( (n * 10 + 500)       / 1000       ))e-1"
  else printf "%d" "$n"; fi
}

# Resolve rate-limit source: stdin .rate_limits (v2.1.6+) > cached OAuth JSON.
# When stdin already has the values we skip the API call entirely — still kick
# the background refresher for the cache-fallback path on older versions.
if [ -z "$s_util" ] && [ -z "$w_util" ]; then
  IFS=$'\x1f' read -r s_util s_reset_epoch w_util w_reset_epoch _ < <(read_limits_cache)
  # epoch fields from cache are actually ISO strings; rename for clarity below.
fi
limits_block=$(build_limits_block "$s_util" "$s_reset_epoch" "$w_util" "$w_reset_epoch")
daily_block=$(build_daily_block)

printf "%s\n" "$line1"
[ -n "$limits_block" ] && printf "%s\n" "$limits_block"
if [ -n "$limits_block" ] && [ -n "$daily_block" ]; then
  printf "  %s────────────────────────────────────────────────────%s\n" "$C_MUTED" "$C_RESET"
fi
[ -n "$daily_block" ] && printf "%s\n" "$daily_block"
