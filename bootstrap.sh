#!/bin/bash

printmsg() {
  echo -e "\033[1;34m$1\033[0m"
}

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.macos` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

printmsg "*** Check prerequisite ***"
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

printmsg "*** Install HomeBrew ***"
if test ! $(which brew); then
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

printmsg "*** Install binaries and applications via Homebrew ***"
brew update
brew tap homebrew/bundle
brew bundle --file=$DOTFILE_DIR/Brewfile
brew cleanup

printmsg "*** Set macOS system configurations ***"
sh .macos

printmsg "*** Set git configurations ***"
[ ! -f $HOME/.gitconfig ] && ln -nfs $DOTFILE_DIR/.gitconfig $HOME/.gitconfig

printmsg "*** Install virtualenvwrapper via pip3 ***"
pip3 install virtualenvwrapper

printmsg "*** Change default shell to zsh, install oh-my-zsh and set configuration ***"
echo "$(which zsh)"| sudo tee -a /etc/shells
chsh -s $(which zsh)
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)" -s --batch
if [ -f $HOME/.zshrc ]; then
  cp $HOME/.zshrc $HOME/.zshrc.backup
fi
ln -nfs $DOTFILE_DIR/.zshrc $HOME/.zshrc
source $HOME/.zshrc


printmsg "*** Install Visual Studio Code extensions ***"
if test $(which code); then
  code --install-extension eg2.tslint
  code --install-extension mauve.terraform
  code --install-extension ms-vscode.Go
  code --install-extension octref.vetur
  code --install-extension PeterJausovec.vscode-docker
  code --install-extension esbenp.prettier-vscode

  if [ -f $HOME/Library/Application\ Support/Code/User/settings.json ]; then
    cp $HOME/Library/Application\ Support/Code/User/settings.json $HOME/Library/Application\ Support/Code/User/settings.json.backup
  fi
  ln -nfs $DOTFILE_DIR/vscode_settings.json $HOME/Library/Application\ Support/Code/User/settings.json
fi


printmsg "*** Copy editor & terminal configurations ***"
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$DOTFILE_DIR/iterm"
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
if [ -f $HOME/.vimrc ]; then
  cp $HOME/.vimrc $HOME/.vimrc.backup
fi
ln -nfs $DOTFILE_DIR/.vimrc $HOME/.vimrc


printmsg "All dotfiles setup completed!\nPlease logout/login to apply some system configurations."
