#!/bin/bash

set -u

input=$(cat)

# Pass-through for WezTerm status bar consumers
echo "$input" > /tmp/claude-code-session.json 2>/dev/null

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
agent=$(echo "$input" | jq -r '.agent.name // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

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

if is_stale "$LIMITS_CACHE" "$LIMITS_TTL"; then
  (refresh_limits >/dev/null 2>&1 &) >/dev/null 2>&1
fi
if is_stale "$DAILY_CACHE" "$DAILY_TTL"; then
  (refresh_daily >/dev/null 2>&1 &) >/dev/null 2>&1
fi

# Format "resets in Nd Nh" / "Nh Nm" / "Nm"
fmt_reset() {
  local iso="$1"
  [ -z "$iso" ] || [ "$iso" = "null" ] && { echo ""; return; }
  local ts now diff d h m
  # API returns UTC timestamps like "2026-04-18T06:00:00.432+00:00". Strip the
  # fractional + offset portion and parse as UTC (-u) so local timezone doesn't
  # get applied twice.
  local iso_trim="${iso%%.*}"
  iso_trim="${iso_trim%%+*}"
  iso_trim="${iso_trim%Z}"
  ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso_trim" +%s 2>/dev/null) || { echo ""; return; }
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

# Read last usage entry from transcript and compute context% against the model's
# window. Prints integer percent or empty if unavailable. Kept cheap: tail the
# last 256 lines and grep in-process; full JSONL walk would be too slow.
context_pct() {
  local tp="$1" m="$2"
  [ -z "$tp" ] || [ ! -f "$tp" ] && return
  # Window size: 1M if model label mentions "1M", else 200k default.
  local window=200000
  [[ "$m" == *"1M"* ]] && window=1000000
  local usage
  usage=$(tail -n 256 "$tp" 2>/dev/null \
    | jq -c 'select(.message.usage != null) | .message.usage' 2>/dev/null \
    | tail -n 1)
  [ -z "$usage" ] && return
  local tokens
  tokens=$(echo "$usage" | jq -r '
    (.input_tokens // 0) +
    (.cache_creation_input_tokens // 0) +
    (.cache_read_input_tokens // 0) +
    (.output_tokens // 0)
  ')
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
ctx=$(context_pct "$transcript_path" "${model:-}")
sep="${C_DIM}|${C_RESET}"

line1="${C_BOLD_WHITE}${model_short}${C_RESET}"
if [ -n "$ctx" ]; then
  line1="$line1 $sep ${C_BLUE}ctx ${ctx}%${C_RESET}"
fi
line1="$line1 $sep ${C_PATH}${short_path}${C_RESET}$(get_git_info)"
[ -n "$agent" ] && line1="$line1 ${C_MAGENTA}[agent:$agent]${C_RESET}"
[ -n "$vim_mode" ] && line1="$line1 ${C_ACCENT}[$vim_mode]${C_RESET}"
[ -n "$output_style" ] && [ "$output_style" != "default" ] && line1="$line1 ${C_GREEN}[$output_style]${C_RESET}"

# Lines 3-5: limits (session / weekly / sonnet) if cache available
build_limits_block() {
  [ ! -f "$LIMITS_CACHE" ] && return
  local data
  data=$(cat "$LIMITS_CACHE" 2>/dev/null) || return

  local rows=""
  for key in session weekly; do
    local util resets label
    util=$(echo "$data" | jq -r ".${key}.utilization // empty")
    resets=$(echo "$data" | jq -r ".${key}.resets_at // empty")
    [ -z "$util" ] || [ "$util" = "null" ] && continue
    local base_color
    case "$key" in
      session) label="Session"; base_color="$C_YELLOW" ;;
      weekly)  label="Weekly "; base_color="$C_GREEN"  ;;
    esac
    # Override with red only when utilization is high enough to warrant warning.
    local color bar left reset_str pct_int
    pct_int=${util%.*}
    if [ "$pct_int" -ge 80 ]; then color="$C_RED"; else color="$base_color"; fi
    bar=$(progress_bar "$util" "$color")
    left=$(printf "%.0f" "$util")
    reset_str=$(fmt_reset "$resets")
    local line
    line=$(printf "  %s%s%s %s %s%3s%%%s" \
      "$C_DIM" "$label" "$C_RESET" "$bar" "$color" "$left" "$C_RESET")
    [ -n "$reset_str" ] && line="$line ${C_DIM}| Resets in $reset_str${C_RESET}"
    rows="${rows}${line}"$'\n'
  done
  printf "%s" "$rows"
}

# Line 6+: daily summary (today / yesterday / 30d)
build_daily_block() {
  [ ! -f "$DAILY_CACHE" ] && return

  # Token split used across all rows:
  #   cache  = cacheReadTokens         (reused from prompt cache)
  #   input  = inputTokens + cacheCreationTokens  (new input that hit the model,
  #            whether or not it ended up creating a cache entry)
  #   output = outputTokens
  # Token format: "1.4B tokens (1.3B/55.0M/1.6M)"
  #   total                   (cache / input / output)
  fmt_row() {
    local label="$1" row="$2"
    [ -z "$row" ] || [ "$row" = "null" ] && return
    local cost cache_t in_t out_t total_t
    cost=$(echo "$row"  | jq -r '.totalCost // 0')
    cache_t=$(echo "$row" | jq -r '.cacheReadTokens // 0')
    in_t=$(echo "$row"    | jq -r '(.inputTokens // 0) + (.cacheCreationTokens // 0)')
    out_t=$(echo "$row"   | jq -r '.outputTokens // 0')
    total_t=$((cache_t + in_t + out_t))
    # Right-align the cost so the "$" column lines up across rows. We format
    # "$1234.56" separately, then pad with spaces inside a fixed-width field.
    local cost_str
    cost_str=$(printf "\$%.2f" "$cost")
    printf "  %s%-10s%s%s%22s%s %s| %s tok (%s/%s/%s)%s\n" \
      "$C_DIM" "$label" "$C_RESET" \
      "$C_LABEL" "$cost_str" "$C_RESET" \
      "$C_DIM" "$(human_num "$total_t")" \
      "$(human_num "$cache_t")" "$(human_num "$in_t")" "$(human_num "$out_t")" \
      "$C_RESET"
  }

  local today
  today=$(jq -r '.daily[-1] // empty' "$DAILY_CACHE" 2>/dev/null)
  fmt_row "Today" "$today"

  local last7
  last7=$(jq -c '{
    totalCost:           ([.daily[-7:][] | .totalCost]           | add // 0),
    cacheReadTokens:     ([.daily[-7:][] | .cacheReadTokens]     | add // 0),
    inputTokens:         ([.daily[-7:][] | .inputTokens]         | add // 0),
    cacheCreationTokens: ([.daily[-7:][] | .cacheCreationTokens] | add // 0),
    outputTokens:        ([.daily[-7:][] | .outputTokens]        | add // 0)
  }' "$DAILY_CACHE" 2>/dev/null)
  [ -n "$last7" ] && fmt_row "Last 7d" "$last7"
}

human_num() {
  local n="$1"
  [ -z "$n" ] && { echo "0"; return; }
  awk -v n="$n" 'BEGIN{
    if (n >= 1e9) printf "%.1fB", n/1e9;
    else if (n >= 1e6) printf "%.1fM", n/1e6;
    else if (n >= 1e3) printf "%.1fK", n/1e3;
    else printf "%d", n;
  }'
}

limits_block=$(build_limits_block)
daily_block=$(build_daily_block)

printf "%s\n" "$line1"
[ -n "$limits_block" ] && printf "%s\n" "$limits_block"
if [ -n "$limits_block" ] && [ -n "$daily_block" ]; then
  printf "  %s────────────────────────────────────────────────────%s\n" "$C_MUTED" "$C_RESET"
fi
[ -n "$daily_block" ] && printf "%s\n" "$daily_block"
