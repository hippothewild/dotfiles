# Global instructions

- When a multi-step task has a checkable end state (tests pass, build green, file contains X) and you would otherwise stop and wait for "continue", set your own `/goal` with the `self-goal` skill (cmux only). Skip it for tasks that finish in one turn.
