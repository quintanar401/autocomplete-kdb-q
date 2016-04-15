DocEntry = require './doc-entry'

class Sym
  constructor: (s) ->
    @global = false
    @cnt = 0
    @range = []
    @syms = []
    @doc = @proto = null
    if s.cnt
      @deserialize s
    else
      @sym =
        text: s.text
        type: if s.qtype is 'name' then 'function' else 'constant'
        baseScore: 10

  serialize: -> { @cnt, @range, @global, @syms, @sym, @proto, doc: @doc?.serialize()}

  deserialize: (data) ->
    {@cnt, @range, @global, @syms, @sym, @proto, @doc} = data
    @proto.isGlobal = if @global then 'yes' else 'no'
    @doc = new DocEntry @doc if @doc

  updateSym: (s, r, c) ->
    @cnt++
    @global = @global or s.isGlobal is 'yes' or @sym.type is 'constant'
    @range.push r unless @hasRange r
    @sym.baseScore = Math.min @sym.baseScore, if s.qtype is 'name' then (if s.isGlobal is 'yes' then 0 else 10) else 0
    @syms.push col: s.col, line: s.line, isAssign: s.isAssign || false, isGlobal: s.isGlobal || 'no', text: s.text
    @proto ?= @syms[0]
    if c and !@sym.description
      @sym.description = c.getFirstLine()
      @doc = c if c

  hasRange: (r) ->
    for i in @range
      if i[0] is r[0] and i[1] is r[1]
        return true
    false

  inRange: (line) ->
    for r in @range
      if r[0] <= line <= r[1]
        return true
    false

module.exports =
  class SymMap
    constructor: (@globals) -> @map = {}

    serialize: -> name: s, sym: o?.serialize() for s,o of @map

    deserialize: (data) ->
      for i in data
        @map[i.name] = new Sym i.sym
        @globals.addGlobalSym @map[i.name].proto, @map[i.name].doc, i.sym.cnt if @map[i.name].global

    addSym: (sym, range, comment) ->
      wasGlobal = @map[sym.text]?.global || false
      @map[sym.text] = new Sym(sym) unless @map[sym.text]
      @map[sym.text].updateSym sym, range, comment
      @globals.addGlobalSym sym, comment, (if wasGlobal then 1 else @map[sym.text].cnt) if @globals and @map[sym.text].global

    addGlobalSym: (sym, comment, cnt) ->
      return unless sym.text.length > 3
      @addSym sym, [0,1000000], comment
      @map[sym.text].cnt += cnt - 1
      @map[sym.text].syms = []

    delGlobalSym: (sym) ->
      @map[sym.sym.text]?.cnt -= sym.cnt
      @map[sym.sym.text] = null if (@map[sym.sym.text]?.cnt || 0) is 0

    getSymsByName: (name) -> @map[name]?.syms || []

    getSymByName: (name) -> @map[name]

    getSyms: (line, lOnly) ->
      @getSymsByPrefix line, null, lOnly

    getSymsByPrefix: (line, prefix, lOnly) ->
      res = []
      for n,s of @map
        continue unless s
        continue if s.global and lOnly
        continue if s.doc?.getSpec()?.noautocomplete
        continue unless prefix and s.sym.text.startsWith prefix
        continue if s.sym.text.length <= prefix.length or prefix.length is 1
        continue unless s.inRange line
        # score: extern globals - 0, local globals - 1, locals - 11 + distance
        s.sym.score = s.sym.baseScore
        s.sym.score += 1 if !lOnly
        s.sym.score += 1-(1/s.cnt) if s.global
        s.sym.score += 1 if s.sym.description
        if !s.global
          d = 0
          for v in s.syms
            d = Math.max Math.abs(v.line - line), d
            s.sym.score += 1/(d+1)
        s.sym.replacementPrefix = prefix
        res.push s.sym
      res

    getSymsByFn: (res, fn) ->
      for n,s of @map
        res = fn res, s
      res

    destroy: ->
      for s of @map
        @globals?.delGlobalSym @map[s] if @map[s]?.global
        @map[s] = null
      @map = @globals = null
