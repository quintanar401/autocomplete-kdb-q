class Sym
  constructor: (s) ->
    @global = false
    @cnt = 0
    @range = []
    @syms = []
    @sym =
      text: s.text
      type: if s.qtype is 'name' then 'function' else 'constant'
      baseScore: 10

  updateSym: (s, r, c) ->
    @cnt++
    @global = @global or s.isGlobal is 'yes' or @sym.type is 'constant'
    @range.push r unless @hasRange r
    @sym.baseScore = Math.min @sym.baseScore, if s.qtype is 'name' then (if s.isGlobal is 'yes' then 0 else 10) else 0
    @syms.push s
    @sym.description = c if c and !@sym.description

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
    constructor: (@globals) ->
      @map = {}

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

    getSymsByName: (name) ->
      res = []
      for n,s of @map
        res = res.concat s.syms if s?.sym.text is name
      res

    getSyms: (line, lOnly) ->
      @getSymsByPrefix line, null, lOnly

    getSymsByPrefix: (line, prefix, lOnly) ->
      res = []
      for n,s of @map
        continue unless s
        continue if s.global and lOnly
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

    destroy: ->
      for s of @map
        @globals?.delGlobalSym @map[s] if @map[s]?.global
        @map[s] = null
      @map = @globals = null
