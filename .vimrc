" ============================================================================
" Vim Configuration
" Author: Jihwan Chun <jihwan0321@gmail.com>
" Last Modified: 2026-02-12
" ============================================================================

" ============================================================================
" General Settings
" ============================================================================

" Use Vim settings, not Vi - must be first
set nocompatible

" Enable file type detection and plugins
filetype plugin indent on

" Enable syntax highlighting
syntax on

" Set encoding
set encoding=utf-8
set fileencoding=utf-8

" History and undo
set history=1000
set undofile
set undodir=~/.vim/undodir
set undolevels=1000

" Create undo directory if it doesn't exist
if !isdirectory($HOME."/.vim/undodir")
    call mkdir($HOME."/.vim/undodir", "p", 0700)
endif

" ============================================================================
" UI/UX Settings
" ============================================================================

" Line numbers
set number

" Cursor line highlight
set cursorline

" Command line
set showcmd
set wildmenu
set wildmode=longest:full,full

" Statusline
set ruler
set laststatus=2

" Mouse support
set mouse=a

" No bell
set noerrorbells
set novisualbell

" Scrolling
set scrolloff=8
set sidescrolloff=8

" Sign column (only show when needed)
set signcolumn=auto

" Color scheme support
if &t_Co > 2 || has("gui_running")
    set background=dark
endif

" ============================================================================
" Search Settings
" ============================================================================

" Smart search
set incsearch
set hlsearch
set ignorecase
set smartcase

" Clear search highlighting with Esc
nnoremap <silent> <Esc> :nohlsearch<CR><Esc>

" ============================================================================
" Tab and Indentation
" ============================================================================

set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set smarttab
set autoindent
set smartindent

" ============================================================================
" File Handling
" ============================================================================

" No backup files
set nobackup
set nowritebackup
set noswapfile

" Faster update time
set updatetime=300

" Auto-reload files when changed outside vim
set autoread

" Allow backspacing over everything in insert mode
set backspace=indent,eol,start

" ============================================================================
" Clipboard
" ============================================================================

" Use system clipboard
if has('mac')
    set clipboard=unnamed
elseif has('unix')
    set clipboard=unnamedplus
endif

" ============================================================================
" Splits
" ============================================================================

set splitright
set splitbelow

" ============================================================================
" Key Mappings
" ============================================================================

" Don't use Ex mode, use Q for formatting
map Q gq

" Better window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Move lines up/down
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Keep cursor centered when scrolling
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv

" Better indenting in visual mode
vnoremap < <gv
vnoremap > >gv

" ============================================================================
" Auto Commands
" ============================================================================

if has("autocmd")
    augroup vimrc
        autocmd!

        " Jump to last known cursor position when opening a file
        autocmd BufReadPost *
            \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit'
            \ |   exe "normal! g`\""
            \ | endif

        " Set text width for text files
        autocmd FileType text,markdown setlocal textwidth=80

        " Remove trailing whitespace on save
        autocmd BufWritePre * :%s/\s\+$//e

        " Highlight yanked text
        if exists('##TextYankPost')
            autocmd TextYankPost * silent! lua vim.highlight.on_yank {higroup="IncSearch", timeout=200}
        endif
    augroup END
endif

" ============================================================================
" Language-specific Settings
" ============================================================================

" Python
autocmd FileType python setlocal tabstop=4 shiftwidth=4 softtabstop=4

" Go
autocmd FileType go setlocal tabstop=4 shiftwidth=4 softtabstop=4 noexpandtab

" YAML
autocmd FileType yaml setlocal tabstop=2 shiftwidth=2 softtabstop=2

" Makefile (must use tabs)
autocmd FileType make setlocal noexpandtab

" ============================================================================
" Performance
" ============================================================================

" Faster redrawing
set lazyredraw
set ttyfast

" Don't redraw during macros
set lazyredraw

" ============================================================================
" Netrw (built-in file explorer)
" ============================================================================

let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 25
