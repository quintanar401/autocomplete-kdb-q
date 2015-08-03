{CompositeDisposable, Directory} = require 'atom'
Parser = require './parser'
SymMap = require './symMap'
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

    #package
    grammar: null
    parser: null
    itemsToProcess: null
    openedFiles: null
    files: null
    id = 0
    waitForChangingStop: false
    scheduled: false
    projectPaths: null

    constructor: ->
      atom.me = this
      @itemsToProcess = []
      @openedFiles = []
      @files = {}
      @subscriptions = new CompositeDisposable
      @parser = new Parser
      # new file is opened
      @subscriptions.add atom.workspace.observeTextEditors (editor) =>
        return unless editor.getGrammar().scopeName == "source.q"

        # process the new buffer
        if !(editor.getPath() in @openedFiles)
          @addBuffer editor
      @subscriptions.add atom.project.onDidChangePaths (paths) =>
        debug "OnDidChangePaths: #{paths}"
        @updateProjectFiles paths
      @projectPaths = []
      @updateProjectFiles atom.project.getPaths()

    dispose: =>
      @subscriptions.dispose()

    lint: (editor)->
      return new Promise (resolve, reject) =>
        @processBuffer editor.getPath(), editor.getBuffer().getText()
        return resolve [] unless f = @files[editor.getPath()]
        debug 'LINT: '+f.path
        resolve f.errors

    getSuggestions:  ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
      res = []
      path = editor.getPath()
      return res unless prefix = @getPrefix editor, bufferPosition
      for p,f of @files
        res = res.concat (f.map.getSymsByPrefix path, bufferPosition.row, prefix) if @files[p]
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
        if @files[p]
          res.refs = res.refs.concat (f.map.getSymsByName res.name).map (s) ->
            line: s.line+1, col: s.col, file: p, isAssign: s.isAssign, text: s.text
      res

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
      return false if f.modified
      true

    initFile: (path) ->
      return if @files[path]
      @files[path] = path: path, map: new SymMap(path), errors: [], res: null, parseTS: (new Date()).toISOString(), modified: false

    removeFile: (path) ->
      return if @isProjectFile path
      @files[path] = null

    parseFile: (path, text) ->
      try
        debug 'Parsing '+path
        @grammar = atom.grammars.grammarForScopeName('source.q') unless @grammar
        oldTPL = @grammar.maxTokensPerLine
        @grammar.maxTokensPerLine = 1000000
        lines = @grammar.tokenizeLines text
        @grammar.maxTokensPerLine = oldTPL
        @files[path].res = @parser.parseFile lines
        @files[path].errors = @parser.errors.map (e) -> e.filePath = path; e
        @extractVars @files[path]
        @files[path].modified = false
      catch err
        throw err
        console.error 'KDB-Autocomplete: unexpected error: '+err

    extractVars: (file) ->
      for blk in file.res
        continue if blk.stms.stm isnt 'vars'
        for v,i in blk.stms.vars
          startLine = if v.isGlobal is 'no' then blk.startLine else 0
          endLine = if v.isGlobal is 'no' then blk.endLine else 1000000
          file.map.addSym v, [startLine,endLine], if i == 0 then blk.comment else null

    isProjectFile: (path) ->
      for p in @projectPaths
        return true if path.startsWith p
      false

    addBuffer: (editor) ->
      bufferSubs = new CompositeDisposable
      buffer = editor.getBuffer()
      path = editor.getPath()

      @openedFiles.push path
      bufferSubs.add buffer.onDidDestroy =>
        debug 'onDidDestroy: '+path
        @openedFiles = _.without @openedFiles, path
        @removeFile path
        bufferSubs.dispose()
      bufferSubs.add buffer.onDidChange =>
        debug 'onDidChange: '+path
        @waitForChangingStop = true
        return unless f = @files[path]
        f.modified = true
      bufferSubs.add buffer.onDidStopChanging =>
        debug 'onDidStopChanging: '+path
        @waitForChangingStop = false
        @scheduleParseTask()
        @processBuffer path, buffer.getText()
      # file will parsed by onDidStopChanging

    processBuffer: (path, text) ->
      debug "process buffer "+path
      return if @isParsed path
      @initFile path
      @parseFile path, text

    # run project parsing in the background
    scheduleParseTask: ->
      return if @scheduled
      @scheduled = true
      _.delay (=> @processFiles()), 100

    processFiles: ->
      debug 'Process Project'
      @scheduled = false
      return if @waitForChangingStop or @itemsToProcess.length is 0
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
          @scheduleParseTask()
      else
        debug "Processing file #{f.getPath()}"
        f.read(true).then (text) =>
          debug "Loaded #{f.getPath()}"
          @processBuffer f.getPath(), text if @isProjectFile f.getPath()
          @scheduleParseTask()
         , (err) =>
          console.error "autocomplete-kdb-q: can't read #{f.getPath()} with #{err}"
          @scheduleParseTask()

    updateProjectFiles: (paths) ->
      newDirs = []; oldDirs = []
      for p in paths
        if p in @projectPaths
          oldDirs.push p
        else
          newDirs.push p

      debug "Changing project: old:#{oldDirs}, new:#{newDirs}"
      @projectPaths = paths
      opened = for e in atom.workspace.getTextEditors()
        e.getPath()
      for f of @files
        @files[f] = null unless @isProjectFile(f) or f in opened

      @itemsToProcess = newDirs.map (d) -> new Directory(d)
      @scheduleParseTask()
