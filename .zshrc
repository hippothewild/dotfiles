# Path to your oh-my-zsh installation.
export ZSH=/Users/jihwan/.oh-my-zsh

# Disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git wd shrink-path kube-ps1)

# User configuration about locale
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# oh-my-zsh
source $ZSH/oh-my-zsh.sh

# custom prompt theme for oh-my-zsh
function conditional_git_prompt() {
  if git rev-parse --git-dir > /dev/null 2>&1 ; then
    echo " $(git_prompt_info)"
  fi
}
PROMPT='%{$fg[yellow]%}$(shrink_path -l -t)%(?,,%{${fg_bold[white]}%} [%?]) %{$reset_color%}'
RPROMPT='$(kube_ps1)$(conditional_git_prompt)'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[blue]%}("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""

# Path related to Golang
export GO111MODULE=on
export GOPATH=$HOME/dev/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Python and Poetry
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
export PATH="$HOME/.poetry/bin:$PATH"

# Aliases
alias resetdns='sudo networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8'
alias python='python3'
alias pip='pip3'
alias ls='exa'

# Aliases (Kubernetes)
export KUBECONFIG="/Users/jihwan/.kube/config"
alias kubetoken='kubectl -n kube-utils get secret -o json | jq ".items[] | select(.metadata.name | contains(\"kubernetes-dashboard-token\"))" | jq -r ".data.token" | base64 --decode | pbcopy'
alias k='kubectl'
alias kns='kubens'

# Autocompletion
fpath+=~/.zfunc
compinit
