# dotfiles

Jihwan Chun's personal dotfiles for macOS.

## Quick Start

```sh
git clone https://github.com/hippothewild/dotfiles.git
cd dotfiles
./bootstrap
```

## What's Included

| File / Directory       | Description                                                |
| ---------------------- | ---------------------------------------------------------- |
| `bootstrap`            | Main setup script (Homebrew, shell, editor, macOS configs) |
| `Brewfile`             | Homebrew packages, casks, MAS apps, VSCode extensions      |
| `.zshrc`               | Zsh configuration with oh-my-zsh                           |
| `.vimrc`               | Vim configuration                                          |
| `.macos`               | macOS system preferences                                   |
| `.gitconfig`           | Git configuration                                          |
| `wezterm.lua`          | WezTerm terminal configuration                             |
| `vscode_settings.json` | VSCode settings                                            |
| `claude/`              | Claude Code configuration                                  |
| `migration/`           | Machine migration backup/restore scripts                   |

When running the bootstrap script, dotfiles and editor configs are **symlinked** from this repository. Back up any existing configs before running on a machine with your own settings.
