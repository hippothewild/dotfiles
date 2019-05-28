#!/bin/bash

printmsg() {
  echo -e "\033[1;34m$1\033[0m"
}

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

printmsg "*** Set macOS system configurations ***"
# Enable 3-finger drag
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpkadThreeFingerDrag -bool true
# Minimize keyboard input repeat delay and repeat period
defaults write -g InitialKeyRepeat -int 15
defaults write -g KeyRepeat -int 2
# Tab touchpad to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
# Disable Dashboard
defaults write com.apple.dashboard mcx-disabled -bool true
# Don’t show Dashboard as a Space
defaults write com.apple.dock dashboard-in-overlay -bool true
# Hot corner; Bottom left screen corner -> Start screen saver
defaults write com.apple.dock wvous-bl-corner -int 5
defaults write com.apple.dock wvous-bl-modifier -int 0
# For macOS with Korean input, use backquote(`) instead of Korean Won(₩)
if [ ! -f ~/Library/KeyBindings/DefaultkeyBinding.dict ]; then
	mkdir -p ~/Library/KeyBindings
  cat << EOF > ~/Library/KeyBindings/DefaultkeyBinding.dict
{
  "₩" = ("insertText:", "\`");
}
EOF
fi

printmsg "*** Install HomeBrew ***"
if test ! $(which brew); then
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi


printmsg "*** Install binaries and applications via Homebrew ***"
brew update
brew tap homebrew/bundle
brew bundle --file=$DOTFILE_DIR/Brewfile
brew cleanup
brew cask cleanup


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
if [ -d $HOME/Library/Application\ Support/iTerm2/DynamicProfiles ]; then
  ln -nfs $DOTFILE_DIR/iterm2_profile.plist $HOME/Library/Application\ Support/iTerm2/DynamicProfiles/iterm2_profile.plist
fi
if [ -f $HOME/.vimrc ]; then
  cp $HOME/.vimrc $HOME/.vimrc.backup
fi
ln -nfs $DOTFILE_DIR/.vimrc $HOME/.vimrc


printmsg "All dotfiles setup completed!\nPlease logout/login to apply some system configurations."
