#!/bin/sh
# SessionStart hook: mark the cmux sidebar workspace with a 🍙 pill when
# this Claude Code session is routed through xclaude to a non-Anthropic
# backend, so xclaude vs. native/official-Anthropic sessions are visually
# distinguishable in the sidebar without touching the auto-generated title
# (a workspace-action rename would permanently freeze the title, since cmux
# stops auto-updating it once a custom title is set).
#
# xclaude writes the actually-serving model/provider to
# $XCLAUDE_SESSION_MARKER (~/.config/xclaude/sessions/<key>.active) as plain
# KEY=VALUE lines. When that provider is itself "anthropic" (billed Anthropic
# API, or the picker's fully-bypassed "Official Anthropic" row where the marker
# env var is unset entirely), there's nothing cost-saving to flag, so no
# pill. Otherwise the pill shows which backend/model is actually serving.
#
# The status key is per-pane ("xclaude:<surface_id>"), not a single
# workspace-level "xclaude" key. Two xclaude sessions sharing a cmux
# workspace used to clobber each other's pill (last writer won), so flipping
# /model in one showed the other's model. Per-pane keys give each its own
# pill; statusline-command.sh refreshes the same key on every render.
#
# Keyed by CMUX_SURFACE_ID (the pane), not the Claude Code session_id: a
# session_id is NOT stable for the life of a pane — /clear (and a fresh
# --resume into a different transcript) mints a new one, which used to fire
# this hook again under a brand-new key and orphan the old one forever
# (nothing ever calls clear-status for a session_id once Claude Code stops
# reporting it). That produced a sidebar showing every model a pane had EVER
# used, stacking up over a session's lifetime, instead of just the one
# currently serving it. The surface id is the same for the pane's whole life,
# so re-firing on /clear now overwrites the one pill instead of adding another.
# Falls back to the session id if the surface id is ever unset, so this still
# degrades to the old (session-scoped, non-accumulating-within-one-launch)
# behavior rather than silently doing nothing.
#
# Silent: no stdout, since SessionStart stdout is injected into context.

command -v cmux >/dev/null 2>&1 || exit 0
[ -n "$CMUX_WORKSPACE_ID" ] || exit 0

# SessionStart passes the session id in its stdin JSON payload. Fall back to
# "default" so the key is still well-formed if the field is ever absent.
_session_id=$(jq -r '.session_id // ""' 2>/dev/null) || _session_id=""
_key="xclaude:${CMUX_SURFACE_ID:-${_session_id:-default}}"

if [ -n "$XCLAUDE_SESSION_MARKER" ] && [ -f "$XCLAUDE_SESSION_MARKER" ]; then
  provider=$(sed -n 's/^provider=//p' "$XCLAUDE_SESSION_MARKER" | head -1)
  model=$(sed -n 's/^model=//p' "$XCLAUDE_SESSION_MARKER" | head -1 | sed 's/\[[^]]*\]$//')
else
  provider=""
  model=""
fi

if [ -n "$provider" ] && [ "$provider" != "anthropic" ]; then
  cmux set-status "$_key" "🍙 ${model:-xclaude}" --color "#9B9B93" --priority 100 >/dev/null 2>&1
else
  cmux clear-status "$_key" >/dev/null 2>&1
fi

exit 0
