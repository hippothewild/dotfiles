#!/bin/sh
# Stop hook: detect when the model emitted a "legacy XML" tool call as plain
# text (an invoke/parameter XML block instead of the proper antml tool-call
# format). Such text is never parsed as a real tool call, so no
# PreToolUse/PostToolUse hook ever fires — the only place to catch it is here,
# after the model finishes its turn.
#
# Once it happens, the bad XML stays in the transcript and the model imitates its
# own prior output (in-context contamination), so it "keeps happening". We block
# the stop and tell the model to ignore that contaminated example and retry in
# the correct format.
#
# IMPORTANT — avoid false positives: merely *talking about* the legacy format
# (quoting tag names inside backticks or prose, as in this very file or in an
# explanation) must NOT trigger. Real drift has these distinguishing marks:
#   * the tags start at the beginning of a line (not inline in a sentence), and
#   * an invoke open tag and a parameter open tag both appear (a real call has
#     both), and
#   * they are NOT inside a backtick code span / fenced code block.
# We require all of these together before blocking.

input=$(cat)

# Avoid an infinite block loop: if we already blocked once for this reason, the
# stop_hook_active flag is set and we must let the turn end.
if printf '%s' "$input" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
  exit 0
fi

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Pull the text of the last assistant message from the JSONL transcript.
last_text=$(jq -rs '
  [ .[] | select(.type == "assistant") ] | last
  | .message.content // []
  | map(select(.type == "text") | .text) | join("\n")
' "$transcript" 2>/dev/null)

[ -z "$last_text" ] && exit 0

# Strip fenced code blocks and inline backtick spans, so quoting the tags as
# code/examples never trips the detector.
stripped=$(printf '%s' "$last_text" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }   # toggle fenced blocks, drop fence lines
  fence { next }                                # drop everything inside a fence
  { gsub(/`[^`]*`/, ""); print }                # drop inline `...` spans
')

# Line-anchored open tags only (real drift starts a line with the tag). Inline
# mentions inside a sentence are excluded by the ^[[:space:]]* anchor.
has_invoke=$(printf '%s' "$stripped" | grep -cE '^[[:space:]]*<(invoke|tool_use)[[:space:]]+name=')
has_param=$(printf '%s' "$stripped"  | grep -cE '^[[:space:]]*<parameter[[:space:]]+name=')
has_fcalls=$(printf '%s' "$stripped" | grep -cE '^[[:space:]]*<function_calls>')

# Block only when a real malformed call shape is present: either an invoke
# paired with a parameter, or an explicit <function_calls> wrapper.
if { [ "$has_invoke" -gt 0 ] && [ "$has_param" -gt 0 ]; } || [ "$has_fcalls" -gt 0 ]; then
  cat <<'EOF'
{
  "decision": "block",
  "reason": "STOP: Your previous message emitted a tool call as plain XML text (an invoke/parameter block at the start of a line, outside any code span) instead of a real tool call, so it was NOT executed. This is a format-imitation loop: a malformed example is now in your context and you keep copying it. IGNORE the format of your previous output entirely. Re-issue the tool call using the proper antml tool-call mechanism (the same way every successful tool call in this session was made). Do not write any tool invocation as literal text."
}
EOF
  exit 0
fi

exit 0
