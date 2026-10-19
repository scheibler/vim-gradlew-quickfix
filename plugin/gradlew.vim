" gradlew.vim - use the project's topmost Gradle wrapper (gradlew) for :make
" Maintainer: Eric Scheibler <email@eric-scheibler.de>
" License:    GPL v3

if exists('g:loaded_gradlew')
  finish
endif

if !exists('+quickfixtextfunc') || !exists('*bufadd')
  echohl WarningMsg
  echomsg 'gradlew.vim: requires Vim 8.2.0933 or newer'
  echohl None
  finish
endif

let g:loaded_gradlew = 1

augroup gradlew_make
  autocmd!
  autocmd FileType java,kotlin,groovy,xml call gradlew#Setup()
  autocmd QuickFixCmdPost make call gradlew#AfterMake()
augroup END
