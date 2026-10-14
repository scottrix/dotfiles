unlet! skip_defaults_vim
source $VIMRUNTIME/defaults.vim

" plugins, fetched by vim-plug (installed by dotfiles steps/70-shell.sh)
if filereadable(expand('~/.vim/autoload/plug.vim'))
  call plug#begin('~/.vim/plugged')
  Plug 'vim-airline/vim-airline'
  Plug 'vim-airline/vim-airline-themes'
  Plug 'dense-analysis/ale'
  Plug 'airblade/vim-gitgutter'
  Plug 'prabirshrestha/asyncomplete.vim'
  call plug#end()
endif
filetype plugin on
syntax on
set tabstop=4 shiftwidth=4 expandtab
set mouse=r
set number

let g:airline#extensions#ale#enabled = 1
let g:airline_theme='simple'

let g:ale_python_black_options = '-S -l 120'
let b:ale_python_flake8_options = '--max-line-length=120'
let g:ale_completion_enabled = 1

highlight SignColumn ctermbg=black
set signcolumn=yes
highlight GitGutterAdd ctermbg=black ctermfg=white
highlight GitGutterDelete ctermbg=black ctermfg=Red
highlight GitGutterChange ctermbg=black ctermfg=yellow

" Setup Netrw internal filemanager
let g:netrw_keepdir = 0
let g:netrw_winsize = 20
let g:netrw_banner = 0
let g:netrw_list_hide = '\(^\|\s\s\)\zs\.\S\+'
let g:netrw_localcopydircmd = 'cp -r'
hi! link netrwMarkFile Search

nnoremap <leader>dd :Lexplore %:p:h<CR>
nnoremap <leader>da :Lexplore<CR>

function! NetrwMapping()
  nmap <buffer> H u
  nmap <buffer> h -^
  nmap <buffer> l <CR>

  nmap <buffer> . gh
  nmap <buffer> P <C-w>z

  nmap <buffer> L <CR>:Lexplore<CR>
  nmap <buffer> <Leader>dd :Lexplore<CR>

  nmap <buffer> <TAB> mf
  nmap <buffer> <S-TAB> mF
  nmap <buffer> <Leader><TAB> mu

  nmap <buffer> ff %:w<CR>:buffer #<CR>
  nmap <buffer> fe R
  nmap <buffer> fc mc
  nmap <buffer> fC mtmc
  nmap <buffer> fx mm
  nmap <buffer> fX mtmm
  nmap <buffer> f; mx

  nmap <buffer> fl :echo join(netrw#Expose("netrwmarkfilelist"), "\n")<CR>
  nmap <buffer> fq :echo 'Target:' . netrw#Expose("netrwmftgt")<CR>
  nmap <buffer> fd mtfq

  nmap <buffer> bb mb
  nmap <buffer> bd mB
  nmap <buffer> bl gb

endfunction

augroup netrw_mapping
  autocmd!
  autocmd filetype netrw call NetrwMapping()
augroup END
