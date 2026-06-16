#!/bin/sh
# UserPromptSubmit hook: inject a standing reminder that all tool calls must use
# the proper antml tool-call mechanism, never literal XML text. Preventive
# measure that lowers how often the legacy-XML drift starts in the first place.
# Output on stdout from a UserPromptSubmit hook is added to the model's context.
cat <<'EOF'
<system-reminder>Always issue tool calls through the real tool-call mechanism. Never write a tool invocation as literal text (e.g. <invoke name="...">, <parameter name="...">, <function_calls>). Such text is not executed and corrupts subsequent turns.</system-reminder>
EOF
