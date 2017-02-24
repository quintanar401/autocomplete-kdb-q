## 0.5.6
* fix comment parsing
* fix tokenizer issue

## 0.5.5
* fix parse bugs and 13.0 style change

## 0.5.1
* typo fixes

## 0.5.0
* Add the main help page + help on my atom packages
* Add indexes for namespaces, syms, files
* Several bug fixes

## 0.4.0
* Cache autocomplete info
* Add QDoc support
* Add help for stdlib

## 0.3.0
* Add autocomplete cfg file
* Parser and Tokenizer are completely new and incremental, they are fast on small changes.
* Globals for autocomplete are moved into a special map to make the search faster.
* Score for items now include their reference number and comment.

## 0.2.0
* Add ability to process files without a path - Query Results in particular.
* Move main menu into toplevel KDB-Q

## 0.1.0 - First Release
* autocomplete for Q including global vars, local vars, symbols.
* Understands assignment, set function.
* projects files are automatically parsed.
* correct behavior when a file is closed, project dirs are changed.
* linter support: brackets, indentation.
* references
* go-to-definiton
