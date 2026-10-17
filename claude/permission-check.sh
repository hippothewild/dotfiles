#!/bin/bash
# Hybrid permission check - fast pattern matching for safe commands
# Exit 0 with {"ok":true} = approve immediately
# Exit 1 = fall through to LLM evaluation

# Parse the command from JSON input
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.command // empty')

# If no command found, fall through to LLM
if [ -z "$COMMAND" ]; then
  exit 1
fi

# Compound commands (`cd X && cat f`, `a | b`, `a; b`): every segment must be
# safe. Workflow subagents routinely emit `cd <scratchpad> && <read-only cmd>`,
# and judging only the first word (`cd`) used to fall through to the LLM hook,
# whose "uncertain -> deny" answer left the subagent parked on an unsurfaced
# prompt for an hour (2026-08-22/23). Leading `env VAR=..` / `VAR=..` prefixes
# and `(`/`{` grouping are stripped before taking the base word.
segments_safe() {
  local cmd="$1" seg base ok c
  while IFS= read -r seg; do
    seg=$(echo "$seg" | sed -E 's/^[[:space:]]*[({]*[[:space:]]*//; s/^(env[[:space:]]+)?([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]]+)*//')
    [ -z "$seg" ] && continue
    base=$(echo "$seg" | awk '{print $1}' | xargs basename 2>/dev/null)
    ok=false
    for c in "${SAFE_COMMANDS[@]}"; do
      if [ "$base" = "$c" ]; then ok=true; break; fi
    done
    [ "$ok" = true ] || return 1
  done < <(echo "$cmd" | sed -E 's/&&|\|\||;|\|/\n/g')
  return 0
}

# Safe commands that can be auto-approved
SAFE_COMMANDS=(
  # Version control
  "git"
  # Package managers
  "npm" "yarn" "pnpm" "bun"
  # Build tools
  "moon" "make" "go" "cargo" "rustc"
  # Read-only operations
  "ls" "cat" "head" "tail" "less" "more"
  "grep" "rg" "find" "fd" "which" "where" "whereis"
  "pwd" "echo" "printf" "wc" "diff" "file" "stat"
  # Development
  "node" "python" "python3" "ruby" "java" "javac"
  "tsc" "tsx" "npx" "bunx"
  # Testing & linting
  "jest" "vitest" "pytest" "mocha"
  "eslint" "prettier" "golangci-lint" "gofmt"
  # Docker (read operations)
  "docker"
  # GitHub CLI
  "gh"
  # Misc safe
  "date" "cal" "uptime" "whoami" "id" "env" "printenv"
  "curl" "wget" "http"
  # Shell plumbing & read-only text tools; `cd` is what compound commands start with
  "cd" "true" "false" "test" "[" "sort" "uniq" "cut" "tr" "awk" "xargs"
  "basename" "dirname" "realpath" "readlink" "column" "nl" "jq" "yq"
  "du" "df" "tree" "shasum" "sha256sum" "md5" "strings" "seq" "expr" "type" "command"
  "sed"  # read-only use; "sed -i" is caught by DANGEROUS_PATTERNS below
)

# Check every segment of the (possibly compound) command against the safe list
SAFE=false
if segments_safe "$COMMAND"; then
  SAFE=true
fi

# Even if command is "safe", check for dangerous patterns. Matched as literal
# substrings (grep -F): as regexes, "| bash" and "eval $(" were invalid EREs and
# silently never matched (grep printed "empty (sub)expression" on every call).
DANGEROUS_PATTERNS=(
  "rm -rf /"
  "rm -rf ~"
  "rm -rf \$HOME"
  "> /dev/sd"
  "mkfs"
  "dd if="
  "chmod 777"
  "chmod -R 777"
  "chown root"
  "sudo"
  "| bash"
  "| sh"
  "| zsh"
  "eval \$("
  "base64 -d"
  "base64 --decode"
  "sed -i"
  "--in-place"
  ".ssh"
  ".aws"
  ".gnupg"
  "/etc/passwd"
  "/etc/shadow"
  "credentials"
  "secret"
  "password"
  "api_key"
  "API_KEY"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiF -- "$pattern"; then
    # Dangerous pattern found - fall through to LLM
    exit 1
  fi
done

# If safe command and no dangerous patterns, auto-approve
if [ "$SAFE" = true ]; then
  echo '{"ok":true}'
  exit 0
fi

# Not in safe list - fall through to LLM evaluation
exit 1
