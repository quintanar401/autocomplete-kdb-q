{CompositeDisposable, TextBuffer, Emitter} = require 'atom'
Parser = require './parser'
SymMap = require './symMap'
fs = require 'fs'
nodePath = require 'path'

printDebug = false
debug = if printDebug or require('process').env['KDB_DEBUG'] is 'yes'
    (obj) -> console.log  obj
  else
    (obj) ->

module.exports =
class QFile
  constructor: (@cfg) ->
    @opened = @cfg.buffer?
    @modified = true
    @lint = null
    @map = null
    @errors = []
    @subscriptions = new CompositeDisposable
    @emitter = new Emitter
    @subscribe()
    @parse()
    @parseTS = null

  destroy: ->
    @destroyBuffer()
    @emitter.dispose()
    @subscriptions = null
    @lint [] if @lint
    @map?.destroy()
    @errors = []
    @cfg = @lint = @map = @emitter = null

  destroyBuffer: ->
    return unless @cfg.buffer
    @subscriptions?.dispose() if @opened
    @parser?.destroy()
    @cfg.buffer = @parser = null
    @opened = false

  serialize: -> cacheTS: @cacheTS, path: @cfg.path, errors: @errors, map: @map?.serialize()

  deserialize: (data) ->
    @cacheTS = data.cacheTS
    @errors = data.errors
    @map = new SymMap @cfg.globals
    @map.deserialize data.map

  # settings for live buffers
  subscribe: ->
    return unless @cfg.buffer
    debug "subscribing for #{@cfg.path}"
    @subscriptions.add @cfg.buffer.onDidChange => @modified = true
    @subscriptions.add @cfg.buffer.onDidDestroy =>
      debug 'onDidDestroy: ' + @cfg.path
      @destroyBuffer()
      @emitter.emit 'did-destroy', @cfg.path
    @subscriptions.add @cfg.buffer.onDidChangePath (newPath) =>
      oldPath = @cfg.path
      @cfg.path = newPath
      # TODO: initiate update cache
      @emitter.emit 'did-change-path', {oldPath, newPath}

    @parser = new Parser @cfg.buffer
    @parser.onParsed => @processBuffer()

  # one off parse for project's files
  # on each async step check if the file was not destroyed
  parse: ->
    return if @cfg.buffer
    if @cfg.pcfg.cache
      @cfg.cache = nodePath.join @cfg.pcfg.cache, @cfg.path.replace /[\\/\.:]/g, "_"
      debug "checking cache file #{@cfg.cache}"
      fs.stat @cfg.path, (e,stat) =>
        if e or !@cfg
          debug "file not found #{@cfg?.path}"
          return @parseFile()
        @cfg.fileTS = stat.mtime.getTime()
        fs.readFile @cfg.cache, (e, txt) =>
          if e or !@cfg
            debug "cache file not found #{@cfg?.cache}"
            return @parseFile()
          try
            data = JSON.parse txt
            if @cfg.fileTS > data.cacheTS or !(data.path is @cfg.path)
              debug "cache #{@cfg.cache} is outdated"
              return @parseFile()
            @deserialize data
            debug "Deserialization complete"
            @emitter.emit 'updated'
          catch err
            console.log err
            console.error "cache file is invalid: #{@cfg.cache}, error: #{err}"
            return @parseFile()
    else @parseFile()

  parseFile: ->
    return unless @cfg
    debug "parse initiated for #{@cfg.path}"
    @cfg.file.read(true).then (text) =>
      return unless @cfg
      debug "Loaded #{@cfg.file.getPath()}"
      @cfg.buffer = new TextBuffer text
      @parser = new Parser @cfg.buffer
      @parser.onParsed =>
        @processBuffer()
        @destroyBuffer()
        @saveCache() if @cfg.file
     , (err) =>
      console.error "autocomplete-kdb-q: can't read #{@cfg?.file.getPath()} with #{err}"
      @modified = false
      @emitter.emit 'updated'

  processBuffer: ->
    try
      debug "process buffer "+@cfg.path
      @map?.destroy()
      @parseTS = (new Date()).toISOString()
      @errors = @parser.getErrors().map (e) => e.filePath = @cfg.path; e
      @map = @parser.getVars @cfg.globals
      @modified = false
      @lint? @errors
      @lint = null
      @emitter.emit 'updated'
    catch err
      console.error 'KDB-Autocomplete: unexpected error: '+err

  saveCache: ->
    return unless @cfg and @cfg.cache
    @cacheTS = @cfg.fileTS || (new Date()).getTime()
    data = @serialize()
    debug "Saving cache #{@cfg.cache}"
    try
      fs.writeFile @cfg.cache, JSON.stringify(data), (e) =>
        return unless e
        console.error "KDB-Autocomplete: write cache failed: #{@cfg?.cache} with #{e}"
    catch err
      console.error "KDB-Autocomplete: write cache failed: #{@cfg.cache} with #{err}"

  getPath: -> @cfg.path

  getErrors: -> @errors

  getSymMap: -> @map

  isModified: -> @modified

  setLint: (@lint) ->

  onUpdated: (cb) -> @emitter.on 'updated', cb

  onDidChangePath: (cb) -> @emitter.on 'did-changed-path', cb

  onDidDestroy: (cb) -> @emitter.on 'did-destroy', cb
