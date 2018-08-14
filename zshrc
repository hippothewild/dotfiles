# Path to your oh-my-zsh installation.
export ZSH=/Users/jihwan/.oh-my-zsh

# Theme to load. Look in ~/.oh-my-zsh/themes/
ZSH_THEME="wezm"

# Disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"

# Enable command auto-correction.
ENABLE_CORRECTION="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git alias-tips virtualenvwrapper wd)

# User configuration about locale
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# Path related to Golang
export GOPATH=$HOME/dev/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# oh-my-zsh
source $ZSH/oh-my-zsh.sh

# virtualenvwrapper setups
export VIRTUALENVWRAPPER_PYTHON=$(which python3)
export WORKON_HOME=$HOME/.virtualenvs
export VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
source /usr/local/bin/virtualenvwrapper_lazy.sh

# Aliases
alias resetdns='sudo networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8'
alias pip='pip3'