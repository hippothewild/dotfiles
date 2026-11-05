#!/usr/bin/env python3
"""PreToolUse(Bash): deny pkill/pgrep calls with an option after the pattern.

BSD pkill on macOS stops parsing options at the first pattern, so
`pkill -f "^./foo$" -n` treats `-n` as a second regex. With -f that matches
every process whose arguments contain "-n", including the /usr/bin/login
wrappers Rex runs terminals under. On 2026-11-05 one such call ended six
Claude sessions at once.
"""
import json
import re
import shlex
import sys

VALUE_OPTS = set("FGMNPUcdgqstu")  # BSD pkill/pgrep options taking a value
PREFIX = (
    r"(?:^|[;&|({!]\s*|\$\(\s*|\b(?:then|do|else|sudo|exec|command|xargs|nohup)\s+"
    r"|\btimeout\s+\S+\s+|\benv\s+|-c\s+[\"']|\w+=\S*\s+)"
)
CALL = re.compile(PREFIX + r"(?:\S*/)?(pkill|pgrep)\s+(.*)$", re.M)
SIGNAL = re.compile(r"^-(\d+|[A-Z0-9]{2,})$")


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:
        return None


def trailing_option(args):
    """Return the first option-like token after the pattern, if any."""
    tokens = tokenize(args)
    if tokens is None:  # the closing quote of `bash -c "pkill ..."`
        tokens = tokenize(args.rstrip().rstrip("\"'"))
    if tokens is None:
        return None
    seen_pattern = False
    skip = False
    for tok in tokens:
        if tok and set(tok) <= set(";&|()<>"):
            break
        if skip:
            skip = False
        elif tok == "--":
            break
        elif seen_pattern:
            if tok.startswith("-") and len(tok) > 1:
                return tok
        elif SIGNAL.match(tok):
            pass
        elif tok.startswith("-") and len(tok) > 1:
            for i, ch in enumerate(tok[1:], 1):
                if ch in VALUE_OPTS:
                    skip = i == len(tok) - 1
                    break
        else:
            seen_pattern = True
    return None


def check(command):
    for match in CALL.finditer(command):
        tok = trailing_option(match.group(2))
        if tok:
            return match.group(1), tok
    return None


def main():
    command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    hit = check(command)
    if not hit:
        return
    tool, tok = hit
    reason = (
        f"{tool}: `{tok}` comes after the pattern. BSD {tool} on macOS treats it "
        f"as a second regex, so the call matches every process with `{tok}` in "
        "its arguments, including the login wrappers of all Rex terminals. Put "
        f"options before the pattern ({tool} {tok} -f PATTERN), or kill the exact "
        "PID. Check what matches with pgrep first."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))


if __name__ == "__main__":
    main()
