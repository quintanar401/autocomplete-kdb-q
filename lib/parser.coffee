# Q parser
{CompositeDisposable, Emitter} = require 'atom'
_ = require 'underscore-plus'
TokenBuffer = require './tokenBuffer'
SymMap = require './symMap'
DocEntry = require './doc-entry'

typeMap =
  'comment.block.simple.q': 'comment'
  'comment.block.eof.q': 'comment'
  'comment.line.q': 'comment'
  'constant.other.q': 'syscmd'
  'string.quoted.single.q': 'string'
  'keyword.operator.q': 'sysop'
  'keyword.control.q': 'control'
  'constant.language.q': 'number'
  'variable.language.q': 'defaultvars'
  'support.function.q': 'function'
  'constant.numeric.q': 'number'
  'variable.q': 'function'
  'entity.name.q': 'variable'
  'support.constant.q': 'constant'
  'invalid.illegal.q': 'error'
  'meta.brace.open.q': 'lparen'
  'meta.brace.close.q': 'rparen'
  'meta.punctuation.q': ';'
  'ws': 'ws'

controls = /^do|if|while|select|update|delete|exec|from|by$/

module.exports =
  class Parser
    constructor: (buffer) ->
      @emitter = new Emitter
      @tokenizer = new TokenBuffer buffer
      @gen = 0
      @tokenizer.onTokenized =>
        lines = @parseFile @tokenizer.getLines()
        @emitter.emit 'parsed'

    destroy: ->
      @tokenizer.destroy()
      @emitter.dispose()
      @tokenizer = @emitter = null

    onParsed: (cb) -> @emitter.on 'parsed', cb

    getErrors: ->
      errors = []
      errors = errors.concat l.errors for l in @tokenizer.getLines() when l.errors?.length > 0
      errors

    getVars: (globals)->
      map = new SymMap globals
      for l,i in @tokenizer.getLines()
        continue if l.dirty or typeof l.state is 'string' or l.names?.length is 0
        for n in l.names
          startLine = if n.isGlobal is 'no' then i-l.offset else 0
          endLine = if n.isGlobal is 'no' then l.nextBlk else 1000000
          map.addSym n, [startLine,endLine], n.comment || null
      map

    getErr: (msg,line,tok) -> type: 'error', text: msg, range: [[line,tok.col],[line,tok.col+tok.value.length]]

    getTokType: (tok) -> typeMap[tok.scopes[1] || 'ws'] || 'error'

    # lines: { dirty, data: { tokens: { scopes, value } }, gen: 0, nextBlk: N, offset: N, blkChanged: true, names:[], state: XX}
    parseFile: (lines) ->
      maySkip = skipTop = true; state = 'ws'; ns = ''; offset = -1; @gen++
      for l,i in lines
        if skipTop and (l.data.line.length is 0 or /\s/.test l.data.line[0])
          l.state = 'ws'; l.errors = []; l.gen = @gen; maySkip = false
          continue
        offset++
        if l.state and maySkip
          state = l.state unless typeof l.state is 'string'
          skipTop = typeof l.state is 'string'
          continue
        l.errors = []; l.gen = @gen
        prevState = l.state or null
        toks = l.data.tokens
        t0 = @getTokType toks[0]
        maySkip = false
        if t0 is 'comment'
          l.state = 'comment'
          continue
        col = 0; skipTop = false
        for t in toks
          t.col = col
          col += t.value.length
        toks = toks.filter (t) => !(@getTokType(t) in ['ws','comment'])
        if toks.length is 0
          l.state = 'ws'
          continue
        if typeof lines[i-1]?.state is 'string' and lines[i-1].state in ['syscmd','indent-error'] and t0 is 'ws'
          l.state = 'indent-error'
          l.errors.push @getErr "Indented code is unreachable if not preceded by the unindented code", i, {col: 0, value: l.data.line}
          continue
        l.blkStart = t0 isnt 'ws'
        if l.blkStart and typeof state isnt 'string'
          l.errors.push @getErr "Unmatched opening bracket: "+j.value, j.line, j for j in state.parens
        if t0 is 'syscmd'
          state = t0
          l.state = t0
          if /^\\d /.test toks[0].value
            ns = toks[0].value.match(/^\\d\s+(\.[a-zA-Z0-9]*)/)?[1] || ''
            ns = '' if ns is '.'
          continue
        if l.blkStart
          state = parens: [], lvl: 0
          offset = 0
        else
          state = _.deepClone state
        state.ns = ns; l.names = []; l.offset = offset
        l.state = @parseLine l, toks, state, i
        maySkip = _.isEqual l.state, prevState
      @addEOB lines
      @addComments lines
      lines

    parseLine: (l,toks,state,ln) ->
      brkMap = '}':'{', ']':'[', ')':'('
      prevNames = []
      for t,i in toks
        ty = @getTokType t
        nval = toks[i+1]?.value
        if ty is 'lparen'
          state.parens.push value: t.value, line: ln, col: t.col
          state.lvl++ if t.value is '{'
        else if ty is 'rparen'
          if state.parens.length is 0
            l.errors.push @getErr "Unmatched closing bracket: "+t.value, ln, t
          else
            prev = state.parens.pop()
            if brkMap[t.value] isnt prev.value
              l.errors.push @getErr "Unmatched closing bracket: "+t.value, ln, t
              state.parens.push prev
            else if t.value is ']' and prevNames.length>0
              prev = prevNames.pop()
              prev.isAssign = true if nval in [':','::']
              prev.isGlobal = 'yes' if prev.isAssign and nval is '::' # no need to check for :, it is already checked
          state.lvl-- if t.value is '}' and state.lvl>=0
        else if ty in ['variable','function','control'] or (ty is 'sysop' and /^[a-zA-Z]+$/.test t.value)
          v = text: t.value, col: t.col, line: ln, qtype: 'name', isGlobal: 'no', isAssign: false
          v.isGlobal = 'yes' if ty is 'function' or state.lvl is 0 or nval is '::'
          v.isAssign = true if nval in [':','::']
          # TODO: assign will not be set for the non-ns representation
          if v.isGlobal is 'yes' and state.ns isnt '' and t.value[0] isnt '.'
            v.isGlobal = 'file'
            l.names.push v
            v = text: state.ns+'.'+t.value, line: ln, col: t.col, qtype: 'name', isGlobal: 'yes', isAssign: v.isAssign
          prevNames.push v if nval is '[' # a[100]: 100
          l.names.push v
        else if ty is 'constant'
          l.names.push text: t.value, line: ln, col: t.col, qtype: 'symbol'
          l.names.push text: t.value.slice(1), line: ln, col: t.col, qtype: 'name', isGlobal: 'yes', isAssign: true if nval is 'set'
        # ignore these types
        # else if tok.type in ['comment','number','string','control','operator','sysfn','defaultvars',';']
        #  null
        else if ty is 'error'
          l.errors.push @getErr "Unexpected parse error", ln, t
      state

    addComments: (lines) ->
      comment = []; dirty = false
      for l,i in lines
        if l.names?.length>0
          n.comment.updateXY [i,n.col] for n in l.names when n.comment
        if l.state is 'comment'
          dirty = dirty or l.gen is @gen
          comment.push l.data.line.match(/\/(.*)$/)?[1] || ''
          continue
        if l.blkStart and l.names?.length>0 and comment.length>0
          if dirty or l.blkChanged
            name = (l.names.reduce ((prev,nxt)->if prev then prev else if controls.test nxt.text then null else nxt), null) || l.names[0]
            l.blkChanged = false
            name.comment?.destroy()
            name.comment = new DocEntry name.text, comment, [name.line,name.col]
            # l.names[0].comment.addCode @extractCode lines, i
        dirty = false
        comment = []

    addEOB: (lines) ->
      prevJ = lines.length; dirty = false
      for l,j in lines by -1
        dirty = dirty or l.gen is @gen
        l.nextBlk = prevJ-1
        if l.offset is 0
          prevJ = j
          l.blkChanged = dirty
          dirty = false
      null

    extractCode: (lines, i) ->
      ls = []; refs = []
      name = lines[i].names?[0]
      for j in [i..lines[i].nextBlk] by 1
        continue if lines[j].dirty or lines[j].state is 'comment'
        if lines[j].names
          for n in lines[j].names
            refs.push n.text if n.qtype is 'name' and n.isGlobal is 'yes' and !(n.text is name.text) and !(n.text in refs)
        ls.push lines[j].data.tokens
      lines: ls, name: name, refs: refs
