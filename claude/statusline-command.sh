#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract values
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
agent=$(echo "$input" | jq -r '.agent.name // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')

# Get shortened path (similar to shrink-path plugin)
shorten_path() {
  local path="$1"
  local home="$HOME"

  # Replace home with ~
  path="${path/#$home/\~}"

  # If path is too long, shorten intermediate directories
  if [ ${#path} -gt 40 ]; then
    # Split by /
    IFS='/' read -ra parts <<< "$path"
    local result=""
    local last_idx=$((${#parts[@]} - 1))

    for i in "${!parts[@]}"; do
      if [ $i -eq 0 ]; then
        result="${parts[$i]}"
      elif [ $i -eq $last_idx ]; then
        result="$result/${parts[$i]}"
      else
        # Shorten intermediate directories to first letter
        result="$result/${parts[$i]:0:1}"
      fi
    done
    echo "$result"
  else
    echo "$path"
  fi
}

# Get git branch (if in git repo)
get_git_info() {
  if git rev-parse --git-dir > /dev/null 2>&1; then
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    local dirty=""

    # Check if dirty (skip optional locks to avoid blocking)
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      dirty="*"
    fi

    if [ -n "$branch" ]; then
      printf " \033[34m(%s%s)\033[0m" "$branch" "$dirty"
    fi
  fi
}

# Build left side (path in yellow, like your zsh PROMPT)
short_path=$(shorten_path "$cwd")
left=$(printf "\033[33m%s\033[0m" "$short_path")

# Build right side (like your zsh RPROMPT)
right=""

# Add agent info if present
if [ -n "$agent" ]; then
  right="$right \033[35m[agent:$agent]\033[0m"
fi

# Add vim mode if present
if [ -n "$vim_mode" ]; then
  right="$right \033[36m[$vim_mode]\033[0m"
fi

# Add output style if not default
if [ -n "$output_style" ] && [ "$output_style" != "default" ]; then
  right="$right \033[32m[$output_style]\033[0m"
fi

# Add git info (blue with red dirty indicator, like your zsh theme)
git_info=$(get_git_info)
right="$right$git_info"

# Print combined status line
printf "%s%s" "$left" "$right"
