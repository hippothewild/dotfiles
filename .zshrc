# ============================================================================
# Oh-My-Zsh Configuration
# ============================================================================

# Path to your oh-my-zsh installation
export ZSH=$HOME/.oh-my-zsh

# Disable auto-setting terminal title
DISABLE_AUTO_TITLE="true"

# Plugins
plugins=(fzf git kube-ps1 shrink-path wd)

# Locale
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# Load oh-my-zsh
source $HOME/.oh-my-zsh/oh-my-zsh.sh

# ============================================================================
# Custom Prompt Theme
# ============================================================================

function conditional_git_prompt() {
  if git rev-parse --git-dir > /dev/null 2>&1 ; then
    echo " $(_omz_git_prompt_info)"
  fi
}

PROMPT='%{$fg[yellow]%}$(shrink_path -l -t)%(?,,%{${fg_bold[white]}%} [%?]) %{$reset_color%}'
RPROMPT='$(kube_ps1)$(conditional_git_prompt)'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[blue]%}("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""

# ============================================================================
# Homebrew
# ============================================================================

export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# ============================================================================
# Development Tools
# ============================================================================

# VS Code
alias c='code'

# Golang
export GOPATH=$HOME/dev/go
export GOROOT="$(brew --prefix go)/libexec"
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Java (OpenJDK)
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# Node.js
export PATH="/opt/homebrew/opt/node@20/bin:$PATH"

# Python
alias python='python3'
alias pip='pip3'

# Mise (runtime version manager) - https://github.com/jdx/mise
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi

# ============================================================================
# Kubernetes
# ============================================================================

# Kubeconfig - merge all config files from ~/.kube/kubeconfigs
if [ -d "$HOME/.kube/kubeconfigs" ]; then
  export KUBECONFIG=$(find "$HOME/.kube/kubeconfigs" -iname '*.kubeconfig.yaml' -exec echo -n ":{}" \; | cut -c 2-)
fi

# Kubernetes aliases
alias k='kubectl'
alias kx='kubectx'
alias kns='kubens'
alias kubetoken='kubectl -n kube-utils get secret -o json | jq ".items[] | select(.metadata.name | contains(\"kubernetes-dashboard-token\"))" | jq -r ".data.token" | base64 --decode | pbcopy'

# ============================================================================
# Utilities
# ============================================================================

# Use eza instead of ls (modern ls replacement)
alias ls='eza'

# fzf configuration
export FZF_DEFAULT_COMMAND='fd --type f'

# ============================================================================
# Cloud Providers
# ============================================================================

# Google Cloud SDK
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then
  source "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then
  source "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"
fi

# Nebius CLI
if [ -f "$HOME/.nebius/path.zsh.inc" ]; then
  source "$HOME/.nebius/path.zsh.inc"
fi

# ============================================================================
# Node.js Version Managers
# ============================================================================

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# ============================================================================
# Build Tools
# ============================================================================

# moonrepo
export PATH="$HOME/.moon/bin:$PATH"
alias mx='moonx'

# Override make command to use moonx when moon.yml exists
function make() {
  if [ -f ./moon.yml ]; then
    echo "moon.yml found, Using moonx..."
    mx "$@"
  else
    /usr/bin/make "$@"
  fi
}

# ============================================================================
# Shell Completion
# ============================================================================

# Custom completion functions
fpath+=~/.zfunc
autoload -Uz compinit && compinit

# SSH hosts autocompletion - only use hosts from config files
zstyle ':completion:*:(ssh|scp|sftp):*' hosts off
zstyle ':completion:*:(ssh|scp|sftp):*' users off
zstyle ':completion:*:(ssh|scp|sftp):*' tag-order '!*'
zstyle ':completion:*:(ssh|scp|sftp):argument-1:*' tag-order '!*'
zstyle -e ':completion:*:(ssh|scp|sftp):*' hosts 'reply=()'
zstyle -e ':completion:*:(ssh|scp|sftp):*' users 'reply=()'

# Fast SSH completion from config files
SSH_HOSTS=(${(f)"$(grep "^Host " ~/.ssh/config ~/.ssh/config.d/**/*.config 2>/dev/null | awk '{print $2}' | grep -v "*")"})
_ssh_fast() { compadd -a SSH_HOSTS }
compdef _ssh_fast ssh scp sftp
