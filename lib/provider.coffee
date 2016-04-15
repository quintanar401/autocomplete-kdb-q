{CompositeDisposable, Directory, File, TextBuffer} = require 'atom'
SymMap = require './symMap'
QFile = require './file'
_ = require 'underscore-plus'
fs = require 'fs'
nodePath = require 'path'

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
      @files = {}
      @globals = new SymMap null
      @subscriptions = new CompositeDisposable
      # new file is opened
      @subscriptions.add atom.workspace.observeTextEditors (editor) =>
        return unless editor.getGrammar().scopeName is "source.q"
        # process the new buffer
        return if @files[path = @getPath(editor)]?.opened
        @files[path]?.destroy()
        @files[path] = new QFile path: path, buffer: editor.getBuffer(), globals: @globals
        @files[path].onDidChangePath (o) => @updateFilePath(o.oldPath,o.newPath)
        @files[path].onDidDestroy (p) => @removeFile p
      @subscriptions.add atom.project.onDidChangePaths (paths) =>
        debug "OnDidChangePaths: #{paths}"
        @updateProjectFiles paths
      @projectPaths = []
      @projectCfgs = {}
      @updateProjectFiles atom.project.getPaths()

    dispose: =>
      @subscriptions.dispose()
      @subscriptions = null
      f?.destroy() for p,f of @files
      @globals.destroy()
      @globals = null
      @projectCfgs = {}; @projectPaths = [];
      @itemsToProcess = []; @files = {}

    lint: (editor)->
      return new Promise (resolve, reject) =>
        return resolve [] unless f = @files[@getPath editor]
        debug 'LINT: '+f.getPath()
        resolve f.getErrors() unless f.isModified()
        f.setLint resolve

    getSuggestions:  ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
      res = []
      path = @getPath editor
      return res unless prefix = @getPrefix editor, bufferPosition
      res = res.concat (@files[path].getSymMap().getSymsByPrefix bufferPosition.row, prefix, true) if @files[path]?.getSymMap()?
      res = res.concat @globals.getSymsByPrefix bufferPosition.row, prefix, false
      res.sort (x,y) -> if x.score > y.score then -1 else if x.score < y.score then 1 else 0
      res

    getReferences: (editor) ->
      pos = editor.getCursorBufferPosition()
      line = editor.lineTextForBufferRow(pos.row)
      debug "Reference line #{line} at #{pos.column}"
      prefix = @getPrefix editor, pos
      name = prefix + @getPostfix line, pos
      @getReferencesByName name

    getReferencesByName: (name) ->
      res = name: name, refs:[]
      debug "Reference for #{res.name}"
      for p,f of @files
        if f?.getSymMap()?
          res.refs = res.refs.concat (f.getSymMap().getSymsByName res.name).map (s) ->
            line: s.line+1, col: s.col, file: p, isAssign: s.isAssign, text: s.text
      res

    getDoc: (editor) ->
      pos = editor.getCursorBufferPosition()
      line = editor.lineTextForBufferRow(pos.row)
      name = @getPrefix editor, pos
      name += @getPostfix line, pos
      name = name.slice 1 if name[0] is "`"
      res = @getDocByRef name
      if res.length is 0
        name = editor.getQDocName?() or 'qdoc..toplevel'
        res = @getDocByRef name
      res

    getDocByRef: (ref) ->
      if ref is 'qdoc..nsidx'
        res = @extractSymsByFn (res,s) ->
          return res unless s.global or s.doc
          return res if s.sym.text[0] is '`'
          p = (s.sym.text.match /^\.[^\.]*/)?[0] or '(global)'
          p = "<td><a href='kdb://reference/qdoc..nsref#{p}'>#{p}</a></td>"
          res.push p unless p in res
          res
        return "<h2>Namespace Index</h2>"+ (@createTbl res.sort())
      if /^qdoc..nsref/.test ref
        ns = (ref.slice 11)+'.'
        res = @extractSymsByFn (res,s) ->
          return res unless s.global or s.doc
          return res if ns[0] is '.' and !s.sym.text.startsWith ns
          return res if ns[0] is '(' and s.sym.text[0] is '.'
          return res if s.sym.text[0] is '`'
          p = "<td><a href='kdb://reference/#{s.sym.text}'>#{s.sym.text}</a></td>"
          res.push p unless p in res
          res
        x = "<h2>Index for #{ns} namespace</h2>"+ (@createTbl res.sort())
        return x
      if ref is 'qdoc..symidx'
        res = @extractSymsByFn (res,s) ->
          return res unless s.sym.text[0] is '`'
          p = "<td><a href='kdb://reference/#{s.sym.text}'>#{s.sym.text}</a></td>"
          res.push p unless p in res
          res
        return "<h2>Symbol Index</h2>"+ (@createTbl res.sort())
      if ref is 'qdoc..flidx'
        res = []
        for p,f of @files
          res.push p = "<a href='kdb://reference/qdoc..file#{encodeURI p}'>#{p}</a>"
        return "<h2>File Index</h2>#{res.sort().join('<br>')}<br>"
      if /^qdoc..file/.test ref
        fl = ref.slice 10
        return unless m = @files[fl]?.getSymMap()
        res = m.getSymsByFn [], (r,s) ->
          return r unless  s.global or s.doc or s.sym.text[0] is "`"
          p = "<td><a href='kdb://reference/#{s.sym.text}'>#{s.sym.text}</a></td>"
          r.push p unless p in r
          r
        return "<h2>File #{fl} Index</h2>"+ (@createTbl res.sort())
      res = []; lst = null
      for p,f of @files
        if f?.getSymMap()?
          s = f.getSymMap().getSymByName ref
          lst = s if s
          if s?.doc
            s.doc.path = p
            res.push s
      return "<h2>#{ref}</h2>No documentation is available.<br><a href='kdb://showtxtrefs/#{ref}'>Show references</a>|" if res.length is 0 and lst
      return "<h2>Not found</h2>Name #{ref} is not found.<br>" if res.length is 0
      res

    extractSymsByFn: (fn) ->
      res = []
      for p,f of @files
        res = f.getSymMap().getSymsByFn res, fn
      res

    createTbl: (a) ->
      res = ""
      l = Math.ceil(a.length/3)-1
      for i in [0..l]
        res = res + "<tr>#{a[3*i]}#{a[1+3*i]||'<td></td>'}#{a[2+3*i]||'<td></td>'}</tr>"
      "<table class='atom-kdb-reftbl'>"+res+"</table><br>"

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

    removeFile: (path) ->
      @files[path]?.destroy()
      @files[path] = null
      if item = @isProjectFile path
        @itemsToProcess.push item
        @scheduleUpdate()

    updateFilePath: (oldPath,newPath) ->
      @files[newPath]?.destroy()
      @files[newPath] = @files[oldPath]
      @files[oldPath] = null
      if item = @isProjectFile oldPath
        @itemsToProcess.push item
        @scheduleUpdate()

    isProjectFile: (path) ->
      for p,c of @projectCfgs
        return base: p, item: path if path in c.files
      null

    inProjectCfg: (p,path) ->
      return false unless cfg = @projectCfgs[p]
      !(path in cfg.ignorePaths) and !(nodePath.basename(path) in cfg.ignoreNames)

    processFiles: ->
      debug 'Process Project'
      return if @itemsToProcess.length is 0
      f = @itemsToProcess.pop()
      try
        if typeof f.item is 'string'
          debug "Processing item #{f.item}"
          f.item = if (fs.statSync f.item).isFile() then new File f.item else new Directory f.item
        if f.item.isDirectory()
          debug "Processing dir #{f.item.getPath()}"
          f.item.getEntries (err, files) =>
            if err
              console.error "autocomplete-kdb-q: can't read #{f.item.getPath()} with #{err}"
            else
              files = files.filter (file) => (file.isDirectory() or /\.[qk]$/.test file.getPath()) and @inProjectCfg f.base, file.getPath()
              debug "Loaded #{files.length} items"
              @projectCfgs[f.base].files.push i.getPath() for i in files when i.isFile()
              files = files.map (file) -> base: f.base, item: file
              @itemsToProcess = @itemsToProcess.concat files if files.length>0
            @scheduleUpdate()
        else
          debug "Processing file #{f.item.getPath()}"
          path=f.item.getPath()
          if !@files[path] and (f.base in atom.project.getPaths() or @projectCfgs[f.base]?.name is "__internal") and path in @projectCfgs[f.base]?.files
            @files[path] = new QFile path: path, file: f.item, pcfg: @projectCfgs[f.base], globals: @globals
            @files[path].onDidDestroy (p) => @scheduleUpdate()
            @files[path].onUpdated => @scheduleUpdate()
            return
          @scheduleUpdate()
      catch error
        console.error "autocomplete-kdb-q: unexpected error #{error}"

    updateProjectFiles: (paths) ->
      newDirs = []; oldDirs = []
      modPath = nodePath.join atom.packages.getLoadedPackage('autocomplete-kdb-q').path, 'resources'
      paths.push modPath unless modPath in paths
      for p in paths
        if p in @projectPaths
          oldDirs.push p
        else
          newDirs.push p

      debug "Changing project: old:#{oldDirs}, new:#{newDirs}"
      @projectPaths = paths
      for f of @files
        if !(@files[f]?.opened or @isProjectFile(f))
          @files[f]?.destroy()
          @files[f] = null

      newDirs.map (d) =>
        cfg = nodePath.join d, '.autocomplete-kdb-q.json'
        @projectCfgs[d] = ignorePaths: [], ignoreNames: [], ignoreRoot: false, files: [], cache: "", name: ""
        if fs.existsSync cfg
          try
            @projectCfgs[d] = JSON.parse fs.readFileSync cfg
            @projectCfgs[d].files = []
            if @projectCfgs[d].includePaths
              for p in @projectCfgs[d].includePaths
                @itemsToProcess.push base: d, item: (if nodePath.isAbsolute(p) then p else nodePath.join d, p)
            @projectCfgs[d].ignorePaths ?= []
            @projectCfgs[d].ignorePaths = @projectCfgs[d].ignorePaths.map (p) ->
              if nodePath.isAbsolute(p) then p else nodePath.join d, p
            @projectCfgs[d].ignoreNames ?= []
            @projectCfgs[d].ignoreRoot ?= false
            @projectCfgs[d].name ?= nodePath.basename d
            @projectCfgs[d].cache ?= ""
            if cache = @projectCfgs[d].cache
              @projectCfgs[d].cache = if nodePath.isAbsolute cache then cache else nodePath.join d, cache
              try
                fs.statSync @projectCfgs[d].cache
              catch err
                fs.mkdirSync @projectCfgs[d].cache
          catch error
            console.error "Couldn't load #{cfg}: " + error
      newDirs.map (d) => (@itemsToProcess.push base: d, item: new Directory d) unless @projectCfgs[d].ignoreRoot
      @scheduleUpdate()

    scheduleUpdate: -> _.delay (=> @processFiles()), 100
