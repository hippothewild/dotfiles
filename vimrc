" Written by Bram Moolenaar <Bram@vim.org>
" Modified by Jihwan Chun <jihwan0321@gmail.com>
" Last Change: Aug 10 2018

if v:progname =~? "evim"
	finish
endif

" Use Vim settings, rather than Vi settings - This must be first, because it changes other options as a side effect.
set nocompatible

" Allow backspacing over everything in insert mode
set backspace=indent,eol,start

" Do not keep a backup file, use versions instead
set nobackup
set nowritebackup

set nu				" Display line numbers
set history=50		" Keep 50 lines of command line history
set ruler			" Show the cursor position all the time
set showcmd			" Display incomplete commands
set incsearch		" Incremental searching

" Don't use Ex mode, use Q for formatting
map Q gq

" In many terminal emulators the mouse works just fine, thus enable it.
set mouse=an

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
	syntax on
	set hlsearch
endif

" Only do this part when compiled with support for autocommands.
if has("autocmd")
	" Enable file type detection.
	" Use the default filetype settings, so that mail gets 'tw' set to 72,
	" 'cindent' is on in C files, etc.
	" Also load indent files, to automatically do language-dependent indenting.
	filetype plugin indent on

	" Put these in an autocmd group, so that we can delete them easily.
	augroup vimrcEx
	au!

	" For all text files set 'textwidth' to 78 characters.
	autocmd FileType text setlocal textwidth=78
	" When editing a file, always jump to the last known cursor position.
	" Don't do it when the position is invalid or when inside an event handler
	" (happens when dropping a file on gvim).
	" Also don't do it when the mark is in the first line, that is the default
	" position when opening a file.
	autocmd BufReadPost *
 		\ if line("'\"") > 1 && line("'\"") <= line("$") |
		\   exe "normal! g`\"" |
		\ endif
 	augroup END
else
	set autoindent		" always set autoindenting on
endif

" Tab width
set tabstop=2		" Size of a hard tabstop
set shiftwidth=2	" Size of an indent
set softtabstop=2	" Size of a soft tabstop
set expandtab		" Use space instead of tab
set smarttab		" Make the tab key insert spaces to go to the next indent

set encoding=UTF-8
set nohlsearch		" Stop the highlighting for the 'hlsearch' option

" Plugins
call plug#begin('~/.vim/plugged')
Plug 'hashivim/vim-terraform'
call plug#end()
