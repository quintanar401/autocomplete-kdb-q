{CompositeDisposable} = require 'atom'
url = require 'url'

class DocView extends HTMLElement
  destroy: ->
    @subscriptions?.dispose()
    @subscriptions = @container = @model = null
    @remove()

  # thanks to ternjs package
  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace',
      'core:cancel': => @refocus()
      'core:close': => @refocus()
    @classList.add('atom-kdb-doc-view')
    @container = document.createElement('div')
    @appendChild(@container)

  initialize: (@model) ->

  refocus: ->
    @model.docPanel?.hide()
    atom.views.getView(e).focus() if e = atom.workspace.getActiveTextEditor()

  add: (@syms) ->
    if typeof @syms is 'string'
      h = @syms + "<a href='kdb://reference/qdoc..toplevel'>Help</a></div>"
    else
     h = ""
     for s,i in @syms
       h += s.doc.getDoc()
       h += "<div class='text-smaller' style='margin-top: 10px;'><a href='kdb://gotodocdef/#{i}'>Defined in #{s.doc.path} at #{1+s.doc.xy[0]}:#{1+s.doc.xy[1]}</a><br>"
       h += "<a href='kdb://showrefs/#{i}'>Show references</a>|<a href='kdb://reference/qdoc..toplevel'>Help</a></div>"
    @container.innerHTML = h
    lnks = @container.getElementsByTagName 'a'
    l.addEventListener 'click', ((ev)=>@onClick ev) for l in lnks when /^kdb:/.test l?.href

  onClick: (ev) ->
    uri = url.parse ev.srcElement.href || ''
    if uri.host is 'reference'
      @model.showDocByRef decodeURI uri.path.slice 1
    else if uri.host is 'gotodocdef'
      idx = Number.parseInt uri.path.slice 1
      @model.openFileAndGoTo @syms[idx].doc.xy, @syms[idx].doc.path, @syms[idx].doc.name if @syms[idx]
    else if uri.host is 'showrefs'
      idx = Number.parseInt uri.path.slice 1
      @model.findReferenceByName @syms[idx].sym.text if @syms[idx]
    else if uri.host is 'showtxtrefs'
      @model.findReferenceByName decodeURI uri.path.slice 1

module.exports = document.registerElement('atom-kdb-doc-view', prototype: DocView.prototype)
