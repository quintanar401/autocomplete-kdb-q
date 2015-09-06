{CompositeDisposable, Directory, TextBuffer} = require 'atom'
Parser = require './parser'
_ = require 'underscore-plus'
fs = require 'fs'

printDebug = false
debug = if printDebug or require('process').env['KDB_DEBUG'] is 'yes'
    (obj) -> console.log  obj
  else
    (obj) ->

module.exports =
  class Provider
    # automcomplete-plus
    selector: '.source.q'
    disableForSelector: '.source.q .comment'
    inclusionPriority: 1
    excludeLowerPriority: true
    # linter
    grammarScopes: ['source.q']
    scope: 'file'
    lintOnFly: true

    constructor: ->
      @itemsToProcess = []
      @openedFiles = []
      @files = {}
      @subscriptions = new CompositeDisposable
      # new file is opened
      @subscriptions.add atom.workspace.observeTextEditors (editor) =>
        return unless editor.getGrammar().scopeName == "source.q"
        # process the new buffer
        if !(@getPath(editor) in @openedFiles)
          @addBuffer editor
      @subscriptions.add atom.project.onDidChangePaths (paths) =>
        debug "OnDidChangePaths: #{paths}"
        @updateProjectFiles paths
      @projectPaths = []
      @updateProjectFiles atom.project.getPaths()

    dispose: =>
      @subscriptions.dispose()
      @subscriptions = null
      @projectPaths = []; @openedFiles = []; @itemsToProcess = []; @files = {}

    lint: (editor)->
      return new Promise (resolve, reject) =>
        return resolve [] unless f = @files[@getPath editor]
        debug 'LINT: '+f.path
        resolve f.errors unless f.modified
        f.lint = resolve

    getSuggestions:  ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
      res = []
      path = @getPath editor
      return res unless prefix = @getPrefix editor, bufferPosition
      for p,f of @files
        res = res.concat (f.map.getSymsByPrefix bufferPosition.row, prefix, path is f.path) if f?.map?
      res.sort (x,y) -> x.score >= y.score
      res

    getReferences: (editor) ->
      res = name: '', refs:[]
      pos = editor.getCursorBufferPosition()
      line = editor.lineTextForBufferRow(pos.row)
      debug "Reference line #{line} at #{pos.column}"
      prefix = @getPrefix editor, pos
      res.name = prefix + @getPostfix line, pos
      debug "Reference for #{res.name}"
      for p,f of @files
        if f?.map?
          res.refs = res.refs.concat (f.map.getSymsByName res.name).map (s) ->
            line: s.line+1, col: s.col, file: p, isAssign: s.isAssign, text: s.text
      res

    getPath: (editor) ->
      return path if path = editor.getPath()
      editor.getURI()

    getPrefix: (editor, bufferPosition) ->
      regex = /(?:`[\w0-9_:\.]+|[\w0-9_\.]+)$/
      line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
      line.match(regex)?[0] or ''

    getPostfix: (line, bufferPosition) ->
      regex = /^(?:`[\w0-9_:\.]+|[\w0-9_\.]+)/
      line = line.slice bufferPosition.column
      line.match(regex)?[0] or ''

    isParsed: (path) ->
      return false unless f = @files[path]
      true

    initFile: (path) ->
      lint = @files[path]?.lint
      @files[path] = path: path, map: null, errors: null, parseTS: (new Date()).toISOString(), modified: false, lint: lint

    removeFile: (path) ->
      @files[path].modified = false
      @files[path].lint?([])
      @files[path].lint = null
      return if @isProjectFile path
      @files[path] = null

    isProjectFile: (path) ->
      for p in @projectPaths
        return true if path.startsWith p
      false

    addBuffer: (editor) ->
      bufferSubs = new CompositeDisposable
      buffer = editor.getBuffer()
      path = @getPath(editor)
      @initFile path
      @files[path].modified = true
      parser = new Parser buffer
      parser.onParsed => @processBuffer path, parser

      @openedFiles.push path
      bufferSubs.add buffer.onDidChange => @files[path].modified = true
      bufferSubs.add buffer.onDidDestroy =>
        debug 'onDidDestroy: '+path
        @openedFiles = _.without @openedFiles, path
        @removeFile path
        parser.destroy()
        bufferSubs.dispose()
        parser = buffer = bufferSubs = null
      bufferSubs.add buffer.onDidChangePath (newPath) =>
        @openedFiles = _.without @openedFiles, path
        @openedFiles.push newPath
        @initFile newPath
        @files[newPath].map = @files[path].map
        @files[newPath].errors = @files[path].errors
        @removeFile path
        path = newPath

    processBuffer: (path, parser) ->
      try
        debug "process buffer "+path
        st = new Date()
        @initFile path; f = @files[path]
        f.errors = parser.getErrors().map (e) -> e.filePath = path; e
        f.map = parser.getVars()
        f.modified = false
        f.lint?(f.errors)
        f.lint = null
        console.log 'Post Parse: ' + (new Date() - st)
      catch err
        console.error 'KDB-Autocomplete: unexpected error: '+err

    processFiles: ->
      debug 'Process Project'
      return if @itemsToProcess.length is 0
      f = @itemsToProcess.pop()
      if f.isDirectory()
        debug "Processing dir #{f.getPath()}"
        f.getEntries (err, files) =>
          if err
            console.error "autocomplete-kdb-q: can't read #{f.getPath()} with #{err}"
          else
            files = files.filter (f) => f.isDirectory() or /\.[qk]$/.test f.getPath()
            debug "Loaded #{files.length} items"
            @itemsToProcess = @itemsToProcess.concat files if files.length > 0
          _.delay (=> @processFiles()), 100
      else
        debug "Processing file #{f.getPath()}"
        f.read(true).then (text) =>
          debug "Loaded #{f.getPath()}"
          if @isProjectFile f.getPath()
            buffer = new TextBuffer text
            parser = new Parser buffer
            parser.on 'parsed', =>
              @processBuffer f.getPath(), parser
              parser.destroy()
              buffer.destroy()
              parser = buffer = null
              _.delay (=> @processFiles()), 100
          else
            _.delay (=> @processFiles()), 100
         , (err) =>
          console.error "autocomplete-kdb-q: can't read #{f.getPath()} with #{err}"
          _.delay (=> @processFiles()), 100

    updateProjectFiles: (paths) ->
      newDirs = []; oldDirs = []
      for p in paths
        if p in @projectPaths
          oldDirs.push p
        else
          newDirs.push p

      debug "Changing project: old:#{oldDirs}, new:#{newDirs}"
      @projectPaths = paths
      opened = @getPath e for e in atom.workspace.getTextEditors()
      for f of @files
        @files[f] = null unless @isProjectFile(f) or f in opened

      @itemsToProcess = newDirs.map (d) -> new Directory(d)
      _.delay (=> @processFiles()), 100
