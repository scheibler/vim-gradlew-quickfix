" gradlew.vim - use the project's topmost Gradle wrapper (gradlew) for :make
" Maintainer: Eric Scheibler <email@eric-scheibler.de>
" License:    GPL v3

if exists('g:autoloaded_gradlew')
  finish
endif
let g:autoloaded_gradlew = 1

let s:save_cpo = &cpo
set cpo&vim

" ---------------------------------------------------------------------------
" Configuration (override in vimrc)
"
" g:gradlew_error_words / g:gradlew_warning_words
"   Words javac prints before the message, e.g. "File.java:12: error: ..."
"   javac ships translations only for English, German, Japanese and
"   Simplified Chinese (e.g. 'エラー'/'警告', '错误'/'警告'); other locales
"   fall back to English.
"
" g:gradlew_qf_root_relative
"   1: show file names in the quickfix window relative to the project root
"   0: show file names relative to Vim's current directory (Vim default)
" ---------------------------------------------------------------------------
let s:error_words   = get(g:, 'gradlew_error_words',   ['error', 'Fehler'])
let s:warning_words = get(g:, 'gradlew_warning_words', ['warning', 'Warnung'])

" Escape a literal word for use in 'errorformat'
function! s:EfmEscape(word) abort
  return substitute(escape(a:word, '\,'), '%', '%%', 'g')
endfunction

" Use the project's topmost gradlew for :make
function! gradlew#Setup() abort
  " -1 = return all matches upward; the last one is the topmost (the project root)
  let l:all = findfile('gradlew', expand('%:p:h') . ';', -1)
  if empty(l:all)
    return
  endif

  let l:gradlew = fnamemodify(l:all[-1], ':p')
  let l:root    = fnamemodify(l:gradlew, ':h')
  let b:gradle_root = l:root
  let &l:makeprg = shellescape(l:gradlew) . ' -p ' . shellescape(l:root)
        \ . ' --console=plain'

  " AAPT2 link errors (indented, name is resolved in gradlew#AfterMake())
  " must come first, otherwise the javac pattern matches with leading spaces
  let l:efm = ['%E%\s%\+%f:%l: error: %m']

  " javac: multi-line (message, source line, caret line -> column)
  for l:w in s:error_words
    call add(l:efm, '%E%f:%l: ' . s:EfmEscape(l:w) . ': %m')
  endfor
  for l:w in s:warning_words
    call add(l:efm, '%W%f:%l: ' . s:EfmEscape(l:w) . ': %m')
  endfor

  " Android resources: XML parse errors (2 lines) and aapt2 errors
  call extend(l:efm, [
        \ '%E%.%#Failed to compile resource file: %f: . Cause: %.%#[row\,col]:[%l\,%c]',
        \ '%Z%\s%#Message: %m',
        \ '%f:%l: AAPT: %trror: %m',
        \ '%.%#ERROR:%\s%#%f:%l: AAPT: %trror: %m',
        \ ])

  " Gradle build scripts (Groovy DSL):
  " - compiler error with column, followed by source and caret line
  " - fallback: "* Where:" location without message
  call extend(l:efm, [
        \ '%E%\s%#%\a%\+ file ''%f'': %l: %m @ line %\d%\+\, column %c.',
        \ '%\a%\+ file ''%f'' line: %l',
        \ ])

  " kotlin: single line with file:// URI and column
  " order matters: %Z (caret line) before the catch-all %C
  call extend(l:efm, [
        \ '%t: file://%f:%l:%c %m',
        \ '%-Z%p^',
        \ '%-C%.%#',
        \ '%-G%.%#',
        \ ])

  let &l:errorformat = join(l:efm, ',')
endfunction

" Quickfix display: file names relative to the project root or to Vim's
" current directory, depending on g:gradlew_qf_root_relative
function! gradlew#QfText(info) abort
  let l:qf   = getqflist({'id': a:info.id, 'items': 1, 'context': 1})
  let l:root = type(l:qf.context) == v:t_dict ? get(l:qf.context, 'gradle_root', '') : ''
  let l:use_root = get(g:, 'gradlew_qf_root_relative', 1)
  let l:lines = []
  for l:i in range(a:info.start_idx - 1, a:info.end_idx - 1)
    let l:e    = l:qf.items[l:i]
    let l:name = fnamemodify(bufname(l:e.bufnr), ':p')
    if l:use_root && !empty(l:root) && stridx(l:name, l:root . '/') == 0
      let l:name = l:name[len(l:root) + 1 :]
    else
      let l:name = fnamemodify(l:name, ':~:.')
    endif
    let l:pos  = l:e.lnum . (l:e.col > 0 ? ' col ' . l:e.col : '')
    let l:type = l:e.type ==? 'e' ? ' error' : l:e.type ==? 'w' ? ' warning' : ''
    let l:text = substitute(l:e.text, '\n\s*', ' ', 'g')
    call add(l:lines, l:name . '|' . l:pos . l:type . '| ' . l:text)
  endfor
  return l:lines
endfunction

" AAPT2 link errors use "<appid>-<sourceset>-<n>:/<type>/<file>" instead of
" a file path. Search the file in the source set's res/ directory.
function! s:ResolveAaptPath(name, root) abort
  let l:m = matchlist(a:name, '-\(\w\+\)-\d\+:/\(.\+\)$')
  if empty(l:m) || empty(a:root)
    return ''
  endif
  let l:set = l:m[1]
  let l:rel = l:m[2]
  " cheap patterns first, recursive search last; skip generated files
  for l:dir in [
        \ '/src/' . l:set . '/res/',
        \ '/*/src/' . l:set . '/res/',
        \ '/**/src/' . l:set . '/res/',
        \ ]
    let l:found = filter(glob(a:root . l:dir . l:rel, 1, 1), 'v:val !~# "/build/"')
    if !empty(l:found)
      return l:found[0]
    endif
  endfor
  return ''
endfunction

" Post-process the quickfix list after :make in a Gradle project:
" - resolve AAPT2 resource names to the real file in the project
" - remove duplicates (Gradle repeats compiler errors in its failure summary);
"   entries are compared by buffer, line and text, a missing column is taken
"   over from the duplicate
" - drop entries without text (build script "* Where:" fallback) if another
"   entry exists for the same location
" - set the display function for file names
function! gradlew#AfterMake() abort
  if !exists('b:gradle_root')
    return
  endif
  let l:root  = b:gradle_root
  let l:items = filter(getqflist(), 'v:val.valid')
  let l:bogus = {}

  let l:located = {}
  for l:e in l:items
    let l:name = bufname(l:e.bufnr)
    if l:name =~# ':/'
      let l:path = s:ResolveAaptPath(l:name, l:root)
      if !empty(l:path)
        let l:bogus[l:e.bufnr] = 1
        let l:e.bufnr = bufadd(l:path)
      endif
    endif
    if !empty(l:e.text)
      let l:located[l:e.bufnr . ':' . l:e.lnum] = 1
    endif
  endfor

  let l:result = []
  let l:index  = {}
  for l:e in l:items
    if empty(l:e.text)
      if has_key(l:located, l:e.bufnr . ':' . l:e.lnum)
        continue
      endif
      let l:e.text = 'build script error (see Gradle output)'
      let l:e.type = 'e'
    endif
    let l:key = l:e.bufnr . ':' . l:e.lnum . ':' . l:e.text
    if has_key(l:index, l:key)
      let l:kept = l:result[l:index[l:key]]
      if l:kept.col == 0 && l:e.col > 0
        let l:kept.col = l:e.col
      endif
    else
      let l:index[l:key] = len(l:result)
      call add(l:result, l:e)
    endif
  endfor

  call setqflist([], 'r', {
        \ 'items': l:result,
        \ 'context': {'gradle_root': l:root},
        \ 'quickfixtextfunc': function('gradlew#QfText'),
        \ })

  " remove the buffers Vim created for the internal AAPT2 names
  for l:nr in keys(l:bogus)
    if !bufloaded(str2nr(l:nr))
      execute 'silent! bwipeout' l:nr
    endif
  endfor
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
