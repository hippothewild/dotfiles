---
name: self-goal
description: Set a /goal completion condition on this session yourself, so a Stop-hook evaluator keeps you working across turns until it holds. Use when the user asks you to set a goal, or when a long multi-step task has a checkable end state (tests pass, build green, file contains X) and you would otherwise stop and wait for "continue". Not for short tasks finishable in one turn. Requires running inside cmux.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/set-goal.sh *)
---

# self-goal

1. Write ONE completion condition that an evaluator can verify from the
   conversation alone (it cannot run commands or read files). Name the
   evidence you will surface, e.g. "`make test` output shows 0 failures and
   it was run after the last edit". Avoid vague aims ("code is clean").
2. Tell the user in one line what goal you are setting.
3. Run: `${CLAUDE_SKILL_DIR}/scripts/set-goal.sh "<condition>"`
4. Keep working. The goal is set within the current turn (a "Goal set"
   message arrives shortly after); from then on the Stop hook blocks
   stopping until the condition holds, so surface the evidence as you go.

Do not use the script to send anything other than a goal condition. Clearing
a goal (`/goal clear`) is the user's call.
