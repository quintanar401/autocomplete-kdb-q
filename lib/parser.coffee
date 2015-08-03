# Q parser
_ = require 'underscore-plus'

module.exports =
  class Parser
    typeMap:
      'comment.block.simple.q': 'comment'
      'comment.block.eof.q': 'comment'
      'comment.line.q': 'comment'
      'constant.other.q': 'syscmd'
      'string.quoted.single.q': 'string'
      'keyword.operator.q': 'sysop'
      'keyword.control.q': 'control'
      'constant.language.q': 'number'
      'variable.language.q': 'defaultvars'
      'support.function.q': 'sysfn'
      'constant.numeric.q': 'number'
      'variable.q': 'function'
      'entity.name.q': 'variable'
      'support.constant.q': 'constant'
      'invalid.illegal.q': 'error'
      'meta.brace.open.q': 'lparen'
      'meta.brace.close.q': 'rparen'
      'meta.punctuation.q': ';'
      'ws': 'ws'

    errors: null
    currentNS: ''

    # error in 1 or several lines
    reportErrorL: (msg, lines, shift) ->
      shift ?= 0
      l = lines[shift][0]
      @errors.push type: 'error', text: msg, range:[[l.line, 0], [l.line, 79]]

    # errorneus token
    reportErrorT: (msg, tok) ->
      @errors.push type: 'error', text: msg, range:[[tok.line, tok.col], [tok.line, tok.col+tok.value.length]]

    # add misc info to the tokens
    updateLines: (lines) ->
      for l,i in lines
        cl = 0
        for t,j in l
          ty = @typeMap[t.scopes[1] || 'ws'] || 'error'
          _.extend t, col: cl, line: i, type: ty
          cl += t.value.length

    emptyLine: (line) ->
      line.every (tok) -> tok.type in ['comment', 'ws']

    nextToken: (opt) ->
      opt.idx++
      if opt.idx is opt.line.length
        if opt.next.length == 0
          opt.idx = -1
          return value:'', type: 'ws'
        opt.idx = 0
        opt.line = opt.next[0]
        opt.next = opt.next.slice 1
      opt.line[opt.idx]

    skipWS: (opt) ->
      tok = @nextToken opt
      while opt.idx>=0 and tok.type in ['comment', 'ws']
        tok = @nextToken opt
      tok

    # parse a file, divide code into blocks based on indentation
    # attach documentation comments
    parseFile: (lines) ->
      @errors = []; @currentNS = ''
      blk = []; blks = []; cmt = false

      @updateLines lines
      for l,i in lines
        if l[0].type == 'ws'
          blk.push l
          cmt = true
        else
          if cmt
            blks.push blk if blk.length>0
            blk = [l]
          else
            blk.push l
          cmt = !(l[0].type == 'comment')

      blks.push blk if blk.length>0
      return blks.map (b) => @parseBlock b

    # parse a block of code, if it starts with a comment remember it
    parseBlock: (lines) ->
      startLine = lines[0][0].line
      endLine = lines[lines.length-1][0].line || startLine
      topComment = [];  i=0
      while i < lines.length and lines[i][0].type == 'comment'
        topComment.push (lines[i][0].value.match /^\s*(?:\\|\/)*(.*)/)[1] || ''
        i++
      lines = (lines.slice i).filter (l) => !@emptyLine l
      return stms: @parseTStms(lines), startLine: startLine, endLine: endLine, comment: topComment.join '\n'

    # parse top level statements
    parseTStms: (lines) ->
      return [] if lines.length == 0
      l = lines[0]
      if l[0].type == 'syscmd'
        # syscmd can't be followed by the indented code
        if lines.length > 1
          @reportErrorL "Indented code is unreachable after a system command", lines, 1
        # change the current namespace according to \d .ns
        if /^\\d /.test l[0].value
          @currentNS = l[0].value.match(/^\\d\s+(\.[a-zA-Z0-9]*)/)?[1] || ''
          @currentNS = '' if @currentNS is '.'
        return stm: 'syscmd', tok: l[0]
      # comments can't be followed by the indented code
      if l[0].type == 'ws'
        @reportErrorL "Indented code is unreachable if not preceded by the unindented code", lines, 0
        return @parseTStms lines.slice 1
      if l[0].type == 'error'
        @reportErrorL "Unexpected parse error", lines, 0
        return @parseTStms lines.slice 1
      return @parseExpr line: l, idx: 0, next: lines.slice 1

    # parse an expression (find only vars + assignments + brackets)
    parseExpr: (opt) ->
      brk = [] # brackets
      lvl = 0 # functions
      vars = []
      brkMap = '}':'{', ']':'[', ')':'('
      tok = opt.line[opt.idx]

      while opt.idx >= 0
        next = @skipWS opt
        nval = next.value
        # the simplest case - the new ( { or [
        if tok.type is 'lparen'
          brk.push tok
          lvl++ if tok.value is '{'
        else if tok.type is 'rparen'
          if brk.length is 0
            @reportErrorT "Unmatched closing bracket: "+tok.value, tok
          else
            prev = brk.pop()
            if brkMap[tok.value] isnt prev.value
              @reportErrorT "Unmatched closing bracket: "+tok.value, tok
              brk.push prev
            else if prev.v
              prev.v.isAssign = true if tok.value is ']' and nval in [':','::']
              prev.v.isGlobal = 'yes' if prev.v.isAssign and nval is '::' # no need to check for :, it is already checked
              prev.v = null
          lvl-- if tok.value is '}' and lvl>=0
        else if tok.type in ['variable','function']
          v = text: tok.value, line: tok.line, col: tok.col, qtype: 'name', isGlobal: 'no', isAssign: false
          v.isGlobal = 'yes' if tok.type is 'function' or lvl is 0 or nval is '::'
          v.isAssign = true if nval in [':','::']
          # TODO: assign will not be set for the non-ns representation
          if v.isGlobal is 'yes' and @currentNS isnt ''
            v.isGlobal = 'file'
            vars.push v
            v = text: @currentNS+'.'+tok.value, line: tok.line, col: tok.col, qtype: 'name', isGlobal: 'yes', isAssign: v.isAssign
          next.v = v if nval is '[' and !v.isAssign # a[100]: 100
          vars.push v
        else if tok.type is 'constant'
          vars.push text: tok.value, line: tok.line, col: tok.col, qtype: 'symbol'
          vars.push text: tok.value.slice(1), line: tok.line, col: tok.col, qtype: 'name', isGlobal: 'yes', isAssign: true if nval is 'set'
        # ignore these types
        # else if tok.type in ['comment','number','string','control','operator','sysfn','defaultvars',';']
        #  null
        else if tok.type is 'error'
          @reportErrorT "Unexpected parse error", tok

        tok = next

      # report remaining brackets and return
      brk.map (b) => @reportErrorT "Unmatched opening bracket: "+b.value, b

      return stm: 'vars', vars: vars
