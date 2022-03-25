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

# Homebrew
export HOMEBREW_PREFIX="/opt/homebrew";
export HOMEBREW_CELLAR="/opt/homebrew/Cellar";
export HOMEBREW_REPOSITORY="/opt/homebrew";
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}";
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:";
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}";

# Homebrew for Rosetta 2
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
alias ibrew='arch -x86_64 /usr/local/bin/brew'

# Golang
export GOPATH=$HOME/dev/go
export GOROOT="$(brew --prefix golang)/libexec"
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if which pyenv > /dev/null; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
fi
if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi

# Pyenv (rosetta)
alias ipyenv="arch -x86_64 pyenv"

# Node
export PATH="/opt/homebrew/opt/node@14/bin:$PATH"

# Kubernetes
export KUBECONFIG=/Users/jihwan/.kube/config:/Users/jihwan/.kube/config_gangnam:/Users/jihwan/.kube/config_kaist
alias kubetoken='kubectl -n kube-utils get secret -o json | jq ".items[] | select(.metadata.name | contains(\"kubernetes-dashboard-token\"))" | jq -r ".data.token" | base64 --decode | pbcopy'
alias k='kubectl'
alias kns='kubens'

# Misc aliases
alias resetdns='sudo networksetup -setdnsservers en0 1.1.1.1 8.8.8.8'
alias python='python3'
alias pip='pip3'
alias ls='exa'
alias vpdev='kubens aron-backend-dev && kubectl get po -l app=aron-backend -o json | jq ".items[0].metadata.name" | xargs -I{} kubectl port-forward {} 10000:10000'
alias vpprod='kubens aron-backend-prod && kubectl get po -l app=aron-backend -o json | jq ".items[0].metadata.name" | xargs -I{} kubectl port-forward {} 10000:10000'

# linear.app
lnls() {
  curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  --data '{ "query": "{ viewer { assignedIssues { nodes { identifier title state { name type } cycle { number } } } } }" }' \
  https://api.linear.app/graphql \
  | jq -r '.data.viewer.assignedIssues.nodes | map(select(.state.type!="completed" and .state.type!="canceled")) | sort_by(.state.name) | .[] | [.identifier, .state.name, "Cycle " + (.cycle.number | tostring), .title] | join(" | ")'
}

# Google Cloud SDK
if [ -f '/Users/jihwan/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/jihwan/Downloads/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/jihwan/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/jihwan/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Autocompletion
fpath+=~/.zfunc
compinit
