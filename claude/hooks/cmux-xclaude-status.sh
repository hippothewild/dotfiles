#!/bin/sh
# SessionStart hook: mark the cmux sidebar workspace with a 🍚 pill when
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
# Silent: no stdout, since SessionStart stdout is injected into context.

command -v cmux >/dev/null 2>&1 || exit 0
[ -n "$CMUX_WORKSPACE_ID" ] || exit 0

if [ -n "$XCLAUDE_SESSION_MARKER" ] && [ -f "$XCLAUDE_SESSION_MARKER" ]; then
  provider=$(sed -n 's/^provider=//p' "$XCLAUDE_SESSION_MARKER" | head -1)
  model=$(sed -n 's/^model=//p' "$XCLAUDE_SESSION_MARKER" | head -1 | sed 's/\[[^]]*\]$//')
else
  provider=""
  model=""
fi

if [ -n "$provider" ] && [ "$provider" != "anthropic" ]; then
  cmux set-status xclaude "🍚 ${model:-xclaude}" --color "#9B9B93" --priority 100 >/dev/null 2>&1
else
  cmux clear-status xclaude >/dev/null 2>&1
fi

exit 0
