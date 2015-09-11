# autocomplete-kdb-q package

Autocomplete and linter (error checking) provider for KDB+ Q

## Installation

autocomplete-kdb-q requires:
* `language-kdb-q` package for grammar.
* `autocomplete-plus` package for autocomplete support.
* `linter` package for error notifications.

Install them as usual via apm or install page in the settings view.

The last two packages are tremendously useful themselves and can be used with many other languages.

## Status

This the first version thus it doesn't provide any settings and doesn't have much functionality.

It will:
* Process all opened Q/K files for symbols and process all Q/K files in the project directories for symbols.
* Update its state on changes in opened files and project directories. It doesn't monitor files in the project directories though.
* Remember all globals, local variables and symbols. It also remembers symbols with 'set' after them as globals, comments before top level definitions and assignments.
* Show comments in the autocomplete window if they are available.
* Provide via `linter` information about errors in indentation and unmatched brackets.
* Provide reference view for symbols via <kbd>ctrl+shift+r</kbd> or context menu.
* Provide go-to-definition for symbols via <kbd>ctrl+alt+d</kbd> or context menu.

### Autocomplete

Example below shows what info is saved by autocomplete and how it is used.

```
/ This comment will be shown for .im.global
.im.global:100h / globals are names that start with .
if[1b; global: 100] / or names defined outside any function.
`imglobaltoo set 100 / or symbols with set
fn:{[a]  / a is local
  b: 100; / local too
  c:: 100; / global
  d[10]:: 100 / parser is clever enough to understand that d is a global
  : `end / `end is remembered too
 }
\d .my
var: 100 / autocomplete understands this and remembers var as file local and .my.var as global
\d .
```

Autocomplete determines for each name or symbol the following properties:
* It is global, local or local with the file scope (if defined within \d ns). Symbols are all global.
* Range for each occurence. Globals are provided in every file, file locals only in the file of origin and locals only in the code block where they were used. The code block consists of indented lines with an unindented line as the first line.
* It is an assignment or not. This info is used in go-to-definition.
* Any comment before the code block is attached to the first name after it.

### Error reporting

Currently only indentation errors and bracket mismatches are reported.

### References and definitions

You can open the reference view for any symbol or name. Put the cursor on it and select from the context menu `KDB-Q/Find references` or press <kbd>ctrl+shift+r</kbd>. The reference panel will appear, you can select any row or close it with the close button.

You can jump to the definition (assignment) of any name. Put the cursor on it and select from the context menu `KDB-Q/Find definition` or press <kbd>ctrl+alt+d</kbd>. If there are several definitions do this several times. After the last definition you will return to the original place.

## settings

Autocomplete looks for `.autocomplete-kdb-q.json` file in each project directory. This file can contain some settings:
* includePaths - list of paths (relative or absolute) to include into this project.
* ignorePaths - list of paths (relative or absolute) to ignore.
* ignoreRoot - ignore all files or dirs in the project's root directory.
* ignoreNames - ignore these names (like ".svn").

Example:
```
{
  "ignorePaths": ["node_modules"],
  "includePaths": ["C:\\somepath\\test.q","C:\\somedir"],
  "ignoreNames": ["a2014.q",".git"]
}
```
