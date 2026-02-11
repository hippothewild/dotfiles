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

# Extract the base command (first word)
BASE_CMD=$(echo "$COMMAND" | awk '{print $1}' | xargs basename 2>/dev/null)

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
)

# Check if base command is in safe list
SAFE=false
for cmd in "${SAFE_COMMANDS[@]}"; do
  if [ "$BASE_CMD" = "$cmd" ]; then
    SAFE=true
    break
  fi
done

# Even if command is "safe", check for dangerous patterns
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
  "\.ssh"
  "\.aws"
  "\.gnupg"
  "/etc/passwd"
  "/etc/shadow"
  "credentials"
  "secret"
  "password"
  "api_key"
  "API_KEY"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
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
