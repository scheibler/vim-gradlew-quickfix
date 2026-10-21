# vim-gradlew-quickfix

Run the project's topmost Gradle wrapper via `:make` and load javac, Kotlin,
Android resource and Gradle build script errors into the quickfix list,
including the exact column if possible.


## Features

- Searches upward from the current file for the topmost `gradlew`, so it also
  works in multi-module projects (e.g. `app/` submodule).
- Sets `makeprg` buffer-locally to `gradlew -p <project root> --console=plain`.
- Parses:
  - javac errors and warnings, including the column from the caret line (`^`)
  - Kotlin compiler messages (`e: file:///…:line:col message`)
  - KSP messages (e.g. Hilt/Dagger, `e: [ksp] …`); without location the
    first class of the "Dependency trace" is resolved to its source file;
    the cursor jumps to the processed method (`unable to process
    'provideFoo(…)'`) or else to the class declaration
  - Android resource XML parse errors and aapt2 errors
  - AAPT2 link errors; the internal resource name
    (`<appid>-main-42:/layout/foo.xml`) is resolved to the real file
  - Gradle build script errors (Groovy DSL)
- Removes the duplicates that Gradle prints again in its failure summary.
- Shows file names in the quickfix window relative to the project root.
- Supports localized javac messages (default: English and German).
- Leaves `:make` in non-Gradle projects untouched.


## Requirements

- Vim 8.2.0933 or newer (`quickfixtextfunc` per quickfix list, `bufadd()`).
  Vim 9.x is recommended.
- Filetype plugins enabled in your `vimrc`:

  ```vim
  filetype plugin indent on
  ```

- A Gradle wrapper (`gradlew`) in the project root.


## Installation

Native packages (Vim 8+):

```sh
git clone https://github.com/scheibler/vim-gradlew-quickfix ~/.vim/pack/plugins/start/vim-gradlew-quickfix
```

pathogen:

```sh
git clone https://github.com/scheibler/vim-gradlew-quickfix ~/.vim/bundle/vim-gradlew-quickfix
```

If you use the XDG layout, replace `~/.vim` with `~/.config/vim`.

Check that the plugin is active in a Java buffer:

```vim
:verbose set makeprg?
```


## Usage

Open any `.java`, `.kt`, `.gradle` or `.xml` file of the project:

```vim
:make assembleDebug
:copen
```

The plugin is active for the filetypes `java`, `kotlin`, `groovy` and `xml`.


## Configuration

### Localized error strings

javac prints `error:`/`warning:` in the language of the JVM locale. javac
ships translations for English, German, Japanese and Simplified Chinese;
other locales fall back to English. To match a different language, set the
word lists in your `vimrc`:

```vim
let g:gradlew_error_words   = ['error', 'エラー']
let g:gradlew_warning_words = ['warning', '警告']
```

The lists replace the defaults (`['error', 'Fehler']`,
`['warning', 'Warnung']`) completely, so keep `error`/`warning` if English
output can occur.

### File names in the quickfix window

```vim
" 1 (default): relative to the project root
"   app/src/main/java/com/example/MainActivity.java|49 col 16 error| ...
" 0: relative to Vim's current directory (Vim default behaviour)
let g:gradlew_qf_root_relative = 0
```


## Limitations

- AAPT2 link errors contain no column; the cursor jumps to the line start.
- AAPT2 resource names are resolved only below `src/<sourceset>/res/` of the project.
  Errors in resources from libraries keep their internal name.
- `:make` runs synchronously; Vim blocks until Gradle is finished.


## License

GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
