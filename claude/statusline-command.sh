#!/bin/bash

set -u

input=$(cat)

# Persist the stdin snapshot per session. Multiple Claude Code sessions run
# concurrently (e.g. a GLM-proxy session alongside Opus sessions in another
# project); writing all of them to one shared file made each session's
# context-window percentage overwrite the others, so the status line flickered
# between different sessions' ctx values (e.g. 55% <-> 36%). Keying by
# session_id gives each session its own file. A `claude-code-session.json`
# symlink points at the most-recent one for any legacy consumer.
_session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
_session_file="/tmp/claude-code-session-${_session_id:-default}.json"
echo "$input" > "$_session_file" 2>/dev/null
ln -sfn "$_session_file" /tmp/claude-code-session.json 2>/dev/null

# Parse all stdin fields in a single jq call. `read` collapses consecutive
# whitespace in IFS, so we use \x1f (unit separator) to keep empty fields
# distinct. Rate-limit and context fields were added by Claude Code v2.1.6+ —
# when present they let us skip the OAuth usage endpoint and transcript
# parsing entirely.
IFS=$'\x1f' read -r \
  cwd model model_id output_style agent vim_mode transcript_path \
  ctx_pct \
  s_util s_reset_epoch w_util w_reset_epoch \
  _ < <(
  echo "$input" | jq -j '
    [
      (.workspace.current_dir // .cwd // ""),
      (.model.display_name // ""),
      (.model.id // ""),
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
C_PATH=$'\033[38;5;179m'      # muted tan — cwd path
C_GIT=$'\033[38;2;161;178;188m'   # dusty teal-blue — git branch (matches ctx)
C_ACCENT=$'\033[38;5;108m'    # muted sage — costs, primary values
C_LABEL=$'\033[38;5;252m'     # near-white — row labels
C_DIM=$'\033[38;5;244m'       # medium gray — secondary info (visible on dark)
C_MUTED=$'\033[38;5;240m'     # darker gray — empty progress dots
C_GREEN=$'\033[38;2;176;173;139m'   # muted olive — weekly bar (and low util fallback)
C_YELLOW=$'\033[38;2;214;184;152m'  # muted tan/gold — session bar (and medium util fallback)
C_RED=$'\033[38;5;174m'       # dusty rose — high utilization
C_MAGENTA=$'\033[38;5;139m'   # dusty mauve — agent indicator
C_BOLD_WHITE=$'\033[1;38;5;255m'  # bright white + bold — model name
C_BLUE=$'\033[38;2;161;178;188m'      # dusty teal-blue — context indicator (matches git)
C_HOTPINK=$'\033[1;38;5;198m'     # bold hot pink — extra-usage warning

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
#
# A refresher that dies before release_lock (e.g. ccusage hangs, process is
# reaped) would otherwise leave the lockdir behind forever — every later run
# then fails the mkdir and skips the refresh, so the cache never updates again
# (permanent deadlock). Guard against that two ways: callers trap-release on
# exit, and here we reclaim a lockdir whose mtime is older than LOCK_STALE.
LOCK_STALE=600   # 10 min — well past any legitimate refresh
acquire_lock() {
  if mkdir "$1" 2>/dev/null; then
    return 0
  fi
  # Held lock: reclaim it if it's stale (owner presumably died).
  local mtime now
  mtime=$(stat -f %m "$1" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - mtime)) -gt "$LOCK_STALE" ]; then
    rmdir "$1" 2>/dev/null
    mkdir "$1" 2>/dev/null
    return
  fi
  return 1
}
release_lock() {
  rmdir "$1" 2>/dev/null
}

refresh_limits() {
  local lock="$LIMITS_CACHE.lock.d"
  acquire_lock "$lock" || return 0
  # Release on any exit so a mid-refresh death can't leave a stale lock.
  trap 'release_lock "$lock"' RETURN

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
          extra: .extra_usage,
          plan: $plan,
          fetched_at: ($ts | tonumber)
        }' > "$LIMITS_CACHE.tmp" 2>/dev/null && mv "$LIMITS_CACHE.tmp" "$LIMITS_CACHE"
      fi
    fi
  fi
}

refresh_daily() {
  local lock="$DAILY_CACHE.lock.d"
  acquire_lock "$lock" || return 0
  # Release on any exit so a mid-refresh death can't leave a stale lock.
  trap 'release_lock "$lock"' RETURN

  local json
  json=$(bunx ccusage@latest daily --json 2>/dev/null)
  if [ -n "$json" ]; then
    echo "$json" > "$DAILY_CACHE.tmp" && mv "$DAILY_CACHE.tmp" "$DAILY_CACHE"
  fi
}

# Refresh the OAuth usage cache when either:
#   (a) stdin didn't deliver rate_limits (older clients), OR
#   (b) a 5h or weekly bucket has hit 100% — extra-usage credits are being
#       drawn and we want to display them (stdin doesn't carry extra_usage).
# refresh_daily (ccusage) always runs; stdin carries no daily totals.
_limit_hit=0
[ -n "$s_util" ] && [ "${s_util%.*}" -ge 100 ] && _limit_hit=1
[ -n "$w_util" ] && [ "${w_util%.*}" -ge 100 ] && _limit_hit=1
if { [ -z "$s_util" ] && [ -z "$w_util" ]; } || [ "$_limit_hit" = "1" ]; then
  is_stale "$LIMITS_CACHE" "$LIMITS_TTL" && \
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
# When pointed at a local translator/gateway (xclaude / anthropic-local-proxy /
# kiro-gateway), Claude Code still reports its internal model id in stdin, not
# the upstream model actually served. xclaude writes the real upstream model
# to a per-session marker file; read it when the base URL is local.
_alp_base_url="${ANTHROPIC_BASE_URL:-}"
if [ -n "$_alp_base_url" ] && \
   [[ "$_alp_base_url" == *"127.0.0.1"* || "$_alp_base_url" == *"localhost"* ]]; then
  # Per-session marker (xclaude sets XCLAUDE_SESSION_MARKER); fall back to the
  # legacy shared file so each session shows its own model+provider, not the
  # last writer's.
  _alp_marker="${XCLAUDE_SESSION_MARKER:-$HOME/.config/xclaude/active}"
  if [ -f "$_alp_marker" ]; then
    _alp_model=$(sed -n 's/^model=//p' "$_alp_marker" 2>/dev/null)
    # xclaude's marker "model=" line is already "<provider-name>/<model>" in
    # multi-provider mode, so no separate provider-kind tag is appended here.
    [ -n "$_alp_model" ] && model_short="$_alp_model"
    # A /model tier switch mid-session changes stdin's model.id on the very
    # next render, but the marker above is written once at launch and never
    # updated — so a switch from sonnet to opus kept showing the launch-time
    # model. Resolve the CURRENT tier instead: strip xclaude's context-window
    # suffix from model_id, then look it up as a borrowed alias
    # ("alias.<id>=<provider>/<model>", written only for tiers that needed
    # one). A tier with no borrowed alias already sends its real
    # "provider/model" as model_id directly, so that case needs no lookup at
    # all.
    _alp_model_id="${model_id%\[1m\]}"
    if [ -n "$_alp_model_id" ]; then
      if [[ "$_alp_model_id" == */* ]]; then
        model_short="$_alp_model_id"
      else
        _alp_alias=$(sed -n "s/^alias.${_alp_model_id}=//p" "$_alp_marker" 2>/dev/null)
        [ -n "$_alp_alias" ] && model_short="$_alp_alias"
      fi
    fi
    # cmux/hooks/cmux-xclaude-status.sh plants the "xclaude" sidebar pill
    # ("🍚 <model>", once, from SessionStart) so xclaude-routed sessions are
    # visually distinguishable from native-Anthropic ones. It never re-fires
    # mid-session, so a /model tier switch left it showing the launch-time
    # model forever. Refresh the SAME key/color/priority here instead of
    # adding a second pill — this block re-runs on every status line render,
    # so it's what keeps it live. Dedup against a cache file: the status line
    # re-renders continuously, and `cmux set-status` is a socket round trip
    # not worth paying when the value hasn't changed. Backgrounded so a
    # slow/dead socket never adds latency to the status line itself.
    if [ -n "${CMUX_WORKSPACE_ID:-}" ] && [ -n "$model_short" ] && command -v cmux >/dev/null 2>&1; then
      _alp_cmux_cache="/tmp/claude-cmux-model-${_session_id:-default}.last"
      if [ "$(cat "$_alp_cmux_cache" 2>/dev/null)" != "$model_short" ]; then
        printf '%s' "$model_short" > "$_alp_cmux_cache" 2>/dev/null
        (cmux set-status xclaude "🍚 ${model_short}" --color "#9B9B93" --priority 100 >/dev/null 2>&1 &)
      fi
    fi
  fi
fi
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
# Args: s_util s_reset w_util w_reset extra_suffix
#   s_reset/w_reset: ISO-8601 timestamp or epoch seconds (fmt_reset handles both)
#   extra_suffix:    pre-rendered "| Extra $X / $Y" string; appended only to
#                    rows whose utilization has hit 100% (the buckets that are
#                    actually drawing from extra credits).
build_limits_block() {
  local su="$1" sr="$2" wu="$3" wr="$4" extra="${5:-}"
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
    [ -n "$extra" ] && [ "$pct_int" -ge 100 ] && line="$line $extra"
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
fi

# If either bucket has hit 100%, pull extra_usage from the OAuth cache and
# build the suffix "| Extra $X / $Y" (hot-pink, as a warning). The suffix is
# rendered only on 100%+ rows by build_limits_block.
extra_suffix=""
if [ "$_limit_hit" = "1" ] && [ -f "$LIMITS_CACHE" ]; then
  extra_enabled="" extra_used="" extra_limit=""
  IFS=$'\x1f' read -r extra_enabled extra_used extra_limit _ < <(
    jq -j '
      [
        (.extra.is_enabled // false | tostring),
        (.extra.used_credits  // ""),
        (.extra.monthly_limit // ""),
        "."
      ] | join("\u001f")' "$LIMITS_CACHE" 2>/dev/null
  )
  if [ "$extra_enabled" = "true" ] && [ -n "$extra_used" ] && [ -n "$extra_limit" ]; then
    # API reports credits in cents (monthly_limit: 60000 = $600 on Max 20x).
    used_dollars=$(awk -v c="$extra_used"  'BEGIN{ printf "%.2f", c/100 }')
    lim_dollars=$(awk  -v c="$extra_limit" 'BEGIN{ printf "%.2f", c/100 }')
    extra_suffix="${C_DIM}|${C_RESET} ${C_HOTPINK}Extra \$${used_dollars} / \$${lim_dollars}${C_RESET}"
  fi
fi

limits_block=$(build_limits_block "$s_util" "$s_reset_epoch" "$w_util" "$w_reset_epoch" "$extra_suffix")
daily_block=$(build_daily_block)

printf "%s\n" "$line1"
[ -n "$limits_block" ] && printf "%s\n" "$limits_block"
if [ -n "$limits_block" ] && [ -n "$daily_block" ]; then
  printf "  %s────────────────────────────────────────────────────%s\n" "$C_MUTED" "$C_RESET"
fi
[ -n "$daily_block" ] && printf "%s\n" "$daily_block"

# Always exit clean — a trailing falsy test (e.g. empty daily_block) would
# otherwise propagate exit code 1, which makes Claude Code drop the statusline.
exit 0
