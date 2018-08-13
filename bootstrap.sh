#!/bin/bash

# Check prerequisite
if test ! $(which tar); then
  echo 'Install tar/gz to continue.'
  exit 1
fi
if test ! $(which curl); then
    echo 'Install curl to continue.'
    exit 1
fi
if test ! $(which git); then
    echo 'Install git to continue.'
    exit 1
fi

DOTFILE_DIR=$(pwd)

# Install Homebrew
if test ! $(which brew); then
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Install binaries and applications via Homebrew
brew update
brew tap homebrew/bundle
brew bundle --file=$DOTFILE_DIR/Brewfile
brew cleanup
brew cask cleanup

# Set git configuration
[ ! -f $HOME/.gitconfig ] && ln -nfs $DOTFILE_DIR/gitconfig $HOME/.gitconfig

# Change default shell to zsh, install oh-my-zsh and set configuration
chsh -s $(which zsh)
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
[ ! -f $HOME/.zshrc ] && ln -nfs $DOTFILE_DIR/zshrc $HOME/.zshrc
source $HOME/.zshrc

# Install Visual Studio Code extensions
if test $(which code); then
  code --install-extension eg2.tslint
  code --install-extension mauve.terraform
  code --install-extension ms-vscode.Go
  code --install-extension octref.vetur
  code --install-extension PeterJausovec.vscode-docker

  cp $HOME/Library/Application\ Support/Code/User/settings.json $HOME/Library/Application\ Support/Code/User/settings.backup.json
  cp ./vscode_settings.json $HOME/Library/Application\ Support/Code/User/settings.json
fi
