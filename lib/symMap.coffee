class Sym
  sym: null
  range: null
  syms: null
  global: false

  constructor: (s) ->
    @range = []
    @syms = []
    @sym =
      text: s.text
      type: if s.qtype is 'name' then 'function' else 'constant'
      baseScore: if s.qtype is 'name' then (if s.isGlobal is 'yes' then 0 else 10) else 0

  updateSym: (s, r, c) ->
    @global = @global or s.isGlobal is 'yes'
    @range.push r unless @hasRange r
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
    constructor: ->
      @map = {}

    addSym: (sym, range, comment) ->
      @map[sym.text] = new Sym(sym) unless @map[sym.text]
      @map[sym.text].updateSym sym, range, comment

    getSymsByName: (name) ->
      res = []
      for n,s of @map
        res = res.concat s.syms if s.sym.text is name
      res

    getSyms: (line, glOnly) ->
      @getSymsByPrefix line, null, glOnly

    getSymsByPrefix: (line, prefix, glOnly) ->
      res = []
      for n,s of @map
        continue if !s.global and glOnly
        continue unless prefix and s.sym.text.startsWith prefix
        continue if s.sym.text.length <= prefix.length or prefix.length is 1
        continue unless s.inRange line
        # score: extern globals - 0, local globals - 1, locals - 11 + distance
        s.sym.score = s.sym.baseScore
        s.sym.score += 1 if !glOnly
        if !s.global
          d = 0
          for v in s.syms
            d = Math.max Math.abs(v.line - line), d
            s.sym.score += 1/(d+1)
        s.sym.replacementPrefix = prefix
        res.push s.sym
      res
