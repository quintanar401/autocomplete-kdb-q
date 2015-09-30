ReferenceView = require './reference-view'
DocView = require './doc-view'

printDebug = false
debug = if printDebug or require('process').env['KDB_DEBUG'] is 'yes'
    (obj) -> console.log  obj
  else
    (obj) ->

module.exports =
class Reference

  constructor: (provider, state = {}) ->
    @provider = provider

    @definitions = null
    @references = null
    @docSym = null
    @reference = new ReferenceView()
    @reference.initialize(this)
    @referencePanel = atom.workspace.addBottomPanel(item: @reference, priority: 0, visible: false)

    @doc = new DocView
    @doc.initialize(this)
    @docPanel = atom.workspace.addRightPanel(item: @doc, priority: 0, visible: false)

    atom.views.getView(@referencePanel).classList.add('atom-kdb-reference-panel', 'panel-bottom')

    @registerEvents()

  registerEvents: ->
    close = @reference.getClose()
    close.addEventListener('click', (e) =>
      @hide()
      editor = atom.workspace.getActiveTextEditor()
      return unless editor
      view = atom.views.getView(editor)
      view?.focus?()
    )

  goToReference: (idx) ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor
    ref = @references.refs[idx]
    @openFileAndGoTo [ref.line-1, ref.col], ref.file, @references.name

  findReference: ->
    return unless editor = atom.workspace.getActiveTextEditor()
    refs = @provider.getReferences editor
    @showReferences refs

  findReferenceByName: (name) ->
    refs = @provider.getReferencesByName name
    @showReferences refs

  showReferences: (refs) ->
    return unless refs.refs.length>0
    @references = refs
    @referencePanel.show()
    @reference.buildItems @references

  goToDefinition: ->
    return unless editor = atom.workspace.getActiveTextEditor()
    refs = @provider.getReferences editor
    refs.refs = refs.refs.filter (el) -> el.isAssign
    return unless refs.refs.length>0

    if @definitions and refs.name is @definitions.name
      @definitions.idx++
      @definitions.idx = -1 if @definitions.idx >= refs.refs.length
    else
      @definitions = lastPos: editor.getCursorBufferPosition(), file: @getPath(editor), idx: 0, name: refs.name

    if @definitions.idx >= 0
      ref = refs.refs[@definitions.idx]
      @openFileAndGoTo [ref.line-1, ref.col], ref.file, @definitions.name
    else
      @openFileAndGoTo @definitions.lastPos, @definitions.file

  showDoc: ->
    return unless editor = atom.workspace.getActiveTextEditor()
    @docSyms = @provider.getDoc editor
    @doc.add @docSyms if @docSyms
    @docPanel.show()

  showDocByRef: (ref) ->
    @docSyms = @provider.getDocByRef ref
    @doc.add @docSyms if @docSyms
    @docPanel.show()

  hide: ->
    @referencePanel.hide()

  show: ->
    @referencePanel.show()

  destroy: ->
    @reference?.destroy()
    @reference = null

    @referencePanel?.destroy()
    @referencePanel = null

    @doc?.destroy()
    @doc = null

    @docPanel?.destroy()
    @docPanel = null

    @provider = @references = @definitions = @docSyms = null

  openFileAndGoTo: (position, file, name) ->
    debug "Open and go to #{file} at #{position} with #{name}"
    atom.workspace.open(file).then (textEditor) =>
      cursor = textEditor.getLastCursor()
      cursor.setBufferPosition(position)
      @markDefinitionBufferRange(cursor, textEditor, [position, [position[0], position[1]+name.length]])

  markDefinitionBufferRange: (cursor, editor, range) ->
    marker = editor.markBufferRange(range, {invalidate: 'touch'})

    decoration = editor.decorateMarker(marker, type: 'highlight', class: 'atom-kdb-definition-marker', invalidate: 'touch')
    setTimeout (-> decoration?.setProperties(type: 'highlight', class: 'atom-kdb-definition-marker active', invalidate: 'touch')), 1
    setTimeout (-> decoration?.setProperties(type: 'highlight', class: 'atom-kdb-definition-marker', invalidate: 'touch')), 1501
    setTimeout (-> marker.destroy()), 2500

  getPath: (editor) ->
    return path if path = editor.getPath()
    editor.getURI()
