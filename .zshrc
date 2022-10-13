# Path to your oh-my-zsh installation.
export ZSH=/Users/$USERNAME/.oh-my-zsh

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
source /Users/$USERNAME/.oh-my-zsh/oh-my-zsh.sh

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

# Homebrew
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# Golang
export GOPATH=$HOME/dev/go
export GOROOT="$(brew --prefix golang)/libexec"
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# jdk
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# asdf
. /opt/homebrew/opt/asdf/libexec/asdf.sh

# Node
export PATH="/opt/homebrew/opt/node@14/bin:$PATH"

# Kubernetes
export KUBECONFIG=$(for i in $(find /Users/$USERNAME/.kube/kubeconfigs -iname '*.kubeconfig.yaml') ; do echo -n ":$i"; done | cut -c 2-)
alias kubetoken='kubectl -n kube-utils get secret -o json | jq ".items[] | select(.metadata.name | contains(\"kubernetes-dashboard-token\"))" | jq -r ".data.token" | base64 --decode | pbcopy'
alias k='kubectl'
alias kns='kubens'

# Misc aliases
alias resetdns='sudo networksetup -setdnsservers en0 1.1.1.1 8.8.8.8'
alias python='python3'
alias pip='pip3'
alias ls='exa'

# Google Cloud SDK
if [ -f "/Users/$USERNAME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "/Users/$USERNAME/Downloads/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "/Users/$USERNAME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "/Users/$USERNAME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

# Autocompletion
fpath+=~/.zfunc
compinit
