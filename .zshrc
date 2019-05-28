# Path to your oh-my-zsh installation.
export ZSH=/Users/jihwan/.oh-my-zsh

# Theme to load. Look in ~/.oh-my-zsh/themes/
ZSH_THEME="wezm"

# Disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git alias-tips virtualenvwrapper wd)

# User configuration about locale
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# oh-my-zsh
source $ZSH/oh-my-zsh.sh

# Path related to Golang
export GOPATH=$HOME/dev/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Path related to Java
export JAVA_HOME=/Library/Java/Home

# ANTLR4 setups
export CLASSPATH=".:/usr/local/lib/antlr-4.7.2-complete.jar:$CLASSPATH"
alias antlr4='java -Xmx500M -cp "/usr/local/lib/antlr-4.7.2-complete.jar:$CLASSPATH" org.antlr.v4.Tool'
alias grun='java org.antlr.v4.gui.TestRig'

# virtualenvwrapper setups
export VIRTUALENVWRAPPER_PYTHON=$(which python3)
export WORKON_HOME=$HOME/.virtualenvs
export VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
source /usr/local/bin/virtualenvwrapper_lazy.sh

# Aliases
alias resetdns='sudo networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8'
alias pip='pip3'
alias kubetoken='kubectl -n kube-system get secret -o json | jq ".items[] | select(.metadata.name | contains(\"kubernetes-dashboard-token\"))" | jq -r ".data.token" | base64 --decode | pbcopy'
alias kp='kubetoken && kubectl proxy'
alias mtuon='sudo ifconfig en0 mtu 400 && networksetup -getMTU en0'
alias mtuoff='sudo ifconfig en0 mtu 1500 && networksetup -getMTU en0'

# Kops
export NAME=k8s.datatech.pubgda.com
export KOPS_STATE_STORE=s3://pubg-da-kops-state
alias kc="kubectl config use-context"
alias kcd="export NAME=k8s.datatech.pubgda.com && kubectl config use-context k8s.datatech.pubgda.com"
alias kcs="export NAME=k8s.spark.pubgda.com && kubectl config use-context k8s.spark.pubgda.com"


# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh
# tabtab source for slss package
# uninstall by removing these lines or running `tabtab uninstall slss`
[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/slss.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/slss.zsh
