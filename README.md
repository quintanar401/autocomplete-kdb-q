# autocomplete-kdb-q package

Autocomplete, QDoc and linter (error checking) provider for KDB+ Q

## Installation

autocomplete-kdb-q requires:
* `language-kdb-q` package for grammar.
* `autocomplete-plus` package for autocomplete support.
* `linter` package for error notifications.

Install them as usual via apm or install page in the settings view.

The last two packages are tremendously useful themselves and can be used with many other languages.

## Status

Available features:
* Processes all open files and projects for symbols/definitions/documentation.
* Updates automatically when new files are opened or opened files are closed/changed.
* Provides correct autocomplete for Q names.
* Provides via `linter` information about errors in indentation and unmatched brackets.
* Shows short comments for names in the autocomplete window if they are available.
* Provides reference view for symbols via <kbd>ctrl+shift+r</kbd> or context menu.
* Provides go-to-definition for symbols via <kbd>ctrl+alt+d</kbd> or context menu.
* Provides QDoc support for user defined functions.
* Shows help for system and user functions via <kbd>F1</kbd> or context menu.

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

### QDoc support

QDoc is implemented along JavaDoc and is compatible with the already existing QDoc schemas. All standard functions and .Q/.z functions are already documented.

All tags are mutiline except @name, @file, @see, @noautocomplete and @module. @module and @file are not supported atm. All QDoc lines should start with /, all
lines with more than one / are ignored allowing you to add private comments. The Q function or variable name should be on the next line after
the comment block. Note that QDoc doesn't need the code to be correct.

The following tags are supported:
* @name Name - Alternative name for the QDoc entry.
* @desc text - Any html.
* @param Name TypeExpr text - Parameter 'Name' with type defined in 'TypeExpr', text can be any html.
* @key Name TypeExpr text - Key of a dictionary, should follow @param.
* @column Name TypeExpr text - Column of a table, should follow @param.
* @returns TypeExpr text - Description of the returned value.
* @throws Name text - Description of a possible exception. If there are several throws it is better to group them together.
* @example code - Any Q code, it will be shown as if in the editor itself (editor is not used though).
* @see name1 name2 ... - List of QDoc names, links will be added.
* @link as {@link link} or {@link Some descr|link} where link is either a foreign http(s) link or a QDoc name. It can be used inside @desc.
* @noautocomplete - suppress autocomplete for the current name. It can be used in general help articles.

TypeExpr is type or (type name) or (type 1|type 2).

Example:
```
/ The verb xkey sets the primary keys in a table.
/ The left argument is a symbol list of column names, which must belong to the table.
/ The right argument is a table. If passed by reference, it is updated. If passed by value, a new table is returned.
/ @param x (symbol|symbol list) Columns.
/ @param y (symbol|table)  Table to be keyed.
/ @returns (symbol|table) Table is keyed, what is returned depends on the second argument.
/ @example `sym xkey `trade
/ @see cols xcol xcols
xkey
```

If you press <kbd>F1</kbd> on xkey you'll see this:
![help](./resources/keyhelp.png)

Note that QDoc also adds a link to the definition and allows you to request all references to the displayed name.

## settings

Autocomplete looks for `.autocomplete-kdb-q.json` file in each project directory. This file can contain some settings:
* includePaths - list of paths (relative or absolute) to include into this project.
* ignorePaths - list of paths (relative or absolute) to ignore.
* ignoreRoot - ignore all files or dirs in the project's root directory.
* ignoreNames - ignore these names (like ".svn").
* cache - path (relative or absolute) where to save cached data to reduce the start time in large projects.

Example:
```
{
  "ignorePaths": ["node_modules"],
  "includePaths": ["C:\\somepath\\test.q","C:\\somedir"],
  "ignoreNames": ["a2014.q",".git"],
  "cache": ".cache"
}
```
