{CompositeDisposable, Emitter} = require 'atom'
_ = require 'underscore-plus'

changingStopInterval = 1000

module.exports =
class TokenBuffer
  constructor: (@buffer) ->
    @grammar = atom.grammars.grammarForScopeName('source.q')
    @grammar.maxTokensPerLine = 1000000
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    @retokenizeDelayed = _.debounce (=> @retokenize()), changingStopInterval
    @subscriptions.add @buffer.onDidChange (event) =>
      @dirty = true
      @changes.push [event.oldRange, event.newRange]
      @retokenizeDelayed()
    @lines = @getNewLines @buffer.getLineCount()
    @changes = []
    @dirty = true
    _.defer => @retokenize()

  onTokenized: (cb) -> @emitter.on 'tokenized', cb

  getLines: -> @lines

  getNewLines: (n) -> { dirty: true  } for i in [1..n] by 1

  nextDirty: (start) ->
    return -1 if start>=@lines.length
    for i in [start..@lines.length-1] by 1
      return i if @lines[i].dirty
    return -1

  retokenize: ->
    return unless @buffer
    @handleDidChange c for c in @changes
    @changes = []
    _.defer => @startUpdate()

  handleDidChange: (event) ->
    if event[0].end.row is event[1].end.row
      @lines[i] = dirty: true for i in [event[0].start.row..event[0].end.row] by 1
    else
      l = @getNewLines event[1].end.row - event[1].start.row
      @lines[event[0].start.row] = dirty: true
      @lines = @lines.slice(0,event[0].start.row+1).concat(l).concat @lines.slice event[0].end.row+1

  startUpdate: ->
    return unless @buffer
    return if @changes?.length > 0
    if !(@lines.length is @buffer.getLineCount())
      console.error 'Unexpected difference in buffer and tokenBuffer counts'
      @lines = @getNewLines @buffer.getLineCount()
    @updateNextChunk 0

  updateNextChunk: (n) ->
    return unless @buffer
    return if @changes?.length > 0
    if 0 > n = @nextDirty n
      @dirty = false
      @emitter.emit 'tokenized'
      return
    d = new Date
    while true
      if @lines[n]?.dirty
        @lines[n].data = @grammar.tokenizeLine @buffer.lineForRow(n), (if n is 0 then null else @lines[n-1].data.ruleStack), n is 0
        @lines[n].lvl2 = @lines[n].data.openScopeTags.length>1 or @lines[n].data.ruleStack.length>1
        @lines[n].dirty = false
      else
        if n>0 and (@lines[n].lvl2 or @lines[n-1].lvl2)
          @lines[n] = dirty: true
          continue
      n++
      break if @lines.length is n or (new Date) - d > 50
    _.defer => @updateNextChunk n

  destroy: ->
    @subscriptions?.dispose()
    @emitter?.dispose()
    @buffer = @lines = @changes = @grammar = @emitter = null
