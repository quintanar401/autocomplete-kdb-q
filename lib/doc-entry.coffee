# QDoc structure:
# Desc, can be multiline
# @desc - excplicit description
# @param name type or (type) or (type|...) description of this param
# @key xxx typeExpr desc for dictionary keys
# @column xxx typeExpr for columns
# @returns typeExpr description of the return value
# @throws name desc
# @example Q code
# @see .some.value
# inside other tags - {@link desc|.some.value) or desc|http://sss

internalTags = ['link']
tags = ['desc','param','key','pkey','column','returns','throws','example','see','name','module','file','ginfo','noautocomplete']
oneRow = ['name','file','module','see','ginfo','noautocomplete']

processInternalTags = (txt) ->
  txt.replace /\{@link\s+[^\}]*\}/g, (link) ->
    link = link.slice 6,-1
    link = (link.split '|').map (l) -> l.trim()
    link = [link,link] if link.length is 1
    if /^http/.test link[1] then "<a href='#{link[1]}'>#{link[0]}</a>" else "<a href='kdb://reference/#{link[1]}'>#{link[0]}</a>"

preprocess =
  'eof': -> ''
  'desc': (lines) -> processInternalTags lines.join ' '
  'param': (lines) ->
    l = lines[0].match /(\S+)\s+(\([^\)]*\)|\w+)\s+(.*$)/
    return ['badFormat',['error'],lines.join ' '] unless l
    args = if l[2][0] is '('
        l[2].slice(1,-1).split('|').map (e) -> e.trim()
      else [l[2]]
    [l[1],args,l[3]+' '+lines.slice(1).join ' ']
  'key': (lines) -> preprocess['param'](lines)
  'pkey': (lines) ->
    l = preprocess['param'](lines)
    l2 = l[2].trim().match /\((optional=[^\)]*)?\)\s+(.*)/
    return [l[0],l[1],l[2],''] unless l2
    [l[0],l[1],l2[2],l2[1]]
  'column': (lines) -> preprocess['param'](lines)
  'returns': (lines) ->
    lines[0] = 'x '+lines[0]
    (preprocess['param'](lines)).slice 1
  'throws': (lines) ->
    l = lines[0].match /(\S+)\s+(.*$)/
    return ["badFormat",lines.join ' '] unless l
    [l[1],l[2]+' '+lines.slice(1).join ' ']
  'name': (lines) -> lines.join(' ').trim() || 'error'
  'file': (lines) -> preprocess['desc'](lines)
  'module': (lines) -> preprocess['throws'](lines)
  'see' : (lines) -> lines[0].split(' ').map((e) -> e.trim()).filter (e) -> e.length > 0
  'example': (lines) ->
    lines = ((if i is 0 then l else l.slice 1) for l,i in lines)
    (if lines[0].length is 0 then lines.slice 1 else lines).join '\n'
  'ginfo': (lines) -> []
  'noautocomplete': (lines) -> ''

escMap =
  '&': '&amp;'
  '<': '&lt;'
  '>': '&gt;'
  ' ': '&nbsp;'

module.exports =
  class DocEntry
    constructor: (@name,lines,@xy) ->
      if typeof @name is 'string'
        @firstLine = (lines[0] || '').replace(/^\/*/,"");
        @path = null
        @grammar = atom.grammars.grammarForScopeName('source.q')
        @grammar.maxTokensPerLine = 1000000
        lines = lines.filter (l) -> l[0] isnt '/'
        @doc = if lines.length>0 then @parseComment(lines: lines, row: 0) else null
      else  @deserialize @name

    destroy: ->
      @firstLine = @doc = @path = @grammar = null

    serialize: -> { @name, @firstLine, @doc, @xy }

    deserialize: (data) -> { @name, @firstLine, @doc, @xy } = data

    updateXY: (@xy) ->

    getFirstLine: -> @firstLine

    getDoc: -> @doc?.doc

    getSpec: -> @doc?.spec

    getLineTag: (lines) ->
      return ['eof',''] if lines.lines.length <= lines.row
      line = lines.lines[lines.row]
      r = line.match(/^\s*@(\w+)\s*(.*)/)
      if r and r[1] in tags then [r[1],r[2]] else ['',line]

    getTag: (lines) ->
      t = @getLineTag lines
      tag = if t[0] is '' then 'desc' else t[0]
      tlines = [t[1]]; lines.row++
      unless tag in oneRow
        while (t=@getLineTag lines)[0] is ''
          tlines.push t[1]
          lines.row++
      tag: tag, txt: preprocess[tag](tlines)

    # returns {doc,spec} where doc = [tags], spec ={ name, file and etc }
    parseComment: (lines) ->
      doc = []
      spec = {}
      while (t=@getTag lines).tag isnt 'eof'
        if t.tag in ['desc','param','returns','throws','see','ginfo']
          doc.push t
        else if t.tag in ['key','pkey','column'] and doc[doc.length-1]?.tag is 'param'
          t.tag = 'key' if t.tag is 'pkey'
          p = doc[doc.length-1]
          p[t.tag] ?= []
          p[t.tag].push t
        else if t.tag in ['name','file','module','noautocomplete']
          spec[t.tag] = t
        else if t.tag is 'example'
          t.txt = "<div class='lines'>"+(@genHtmlCode t.txt)+"</div>"
          doc.push t
      doc = @generateQDoc doc, spec
      {doc, spec}

    generateQDoc: (doc, spec) ->
      res = "<h2>"+(if spec.name then "#{spec.name.txt}" else @name)+"</h2>"
      isParamBlock = isThrowsBlock = false
      for t,i in doc
        if t.tag is 'param'
          res += "<h3 class='text-highlight'>Parameters:</h3><div class='kdb-params'><ul class='list-tree'>" unless isParamBlock
          isParamBlock = true
          res += "<li class='list-nested-item'><div class='list-item'>"
          res += @genParamSpan t.txt
          if t.key
            res += "<p>Dictionary has the following keys:</p></div><ul class='list-tree'>"
            res += "<li class='list-nested-item'><div class='list-item'>"+(@genParamSpan k.txt)+"</div></li>" for k in t.key
            res += '</ul>'
          else if t.column
            res += "<p>Table has the following columns:</p></div><ul class='list-tree'>"
            res += "<li class='list-nested-item'><div class='list-item'>"+(@genParamSpan k.txt)+"</div></li>" for k in t.key
            res += '</ul>'
          else res += '</div>'
          res += "</li>"
          continue
        if t.tag is 'throws'
          res += "<h3 class='text-highlight'>Throws:</h3><div class='kdb-returns'><ul class='list-group'>" unless isThrowsBlock
          isThrowsBlock = true
          res += "<li class='list-item'><span class='inline-block highlight'>#{t.txt[0]}</span><span class='inline-block'> #{t.txt[1]}</span></li>"
          continue
        res += "</ul></div>" if isParamBlock
        res += "</ul></div>" if isThrowsBlock
        isParamBlock = false
        if t.tag is "desc"
          res += "<p #{if i is 0 then '' else 'class=\'kdb-desc-inside\''}>#{t.txt}</p>"
        else if t.tag is "returns"
          res += "<h3 class='text-highlight'>Returns:</h3><div class='kdb-returns'>#{@genParamSpan ['',t.txt[0],t.txt[1]]}</div>"
        else if t.tag is "see"
          lnks = ("<a href='kdb://reference/#{l}'>#{l}</a>" for l in t.txt) || []
          res += "<h3 class='text-highlight'>See also:</h3> <div class='kdb-returns'>#{lnks.join(', ')}</div>"
        else if t.tag is "example"
          res += "<h3 class='text-highlight'>Example:</h3><div class='kdb-example'>#{t.txt}</div>"
        else if t.tag is 'ginfo'
          res += "<div class='text-info'>This is a generic function that works with all or almost all argument types and shapes.</div>"
      res += "</ul></div>" if isParamBlock
      res += "</ul></div>" if isThrowsBlock
      res

    genParamSpan: (data) ->
      (if data[0] then "<span class='inline-block highlight'>#{data[0]}</span>" else "")+
        "<span class='inline-block text-subtle'>#{data[1].join(', ')}</span> <span class='inline-block'> #{data[2]}</span>"

    addCode: (@code) ->
      @code.lines = @genCode @code.lines

    genHtmlCode: (lines) ->
      if typeof lines is 'string'
        lines = @grammar.tokenizeLines lines
      html = ''
      for l in lines
        html += '<div class="line"><span class="source q">'
        for t in l
          v = t.value.replace /[&<> ]/g, (c) -> escMap[c]
          if t.scopes.length>1
            s = t.scopes[t.scopes.length-1].replace(/\.close\.?|\./g," ")
            html += "<span class='#{s}'>#{v}</span>"
          else
            html += v
        html += '</span></div>'
      html

    genCode: (lines) ->
      html = @genHtmlCode lines
      code = document.createElement 'div'
      code.innerHTML = html
      code
