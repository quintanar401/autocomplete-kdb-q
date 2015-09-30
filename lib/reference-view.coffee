printDebug = false
debug = if printDebug or require('process').env['KDB_DEBUG'] is 'yes'
    (obj) -> console.log  obj
  else
    (obj) ->

class ReferenceView extends HTMLElement
  # thanks to ternjs package
  createdCallback: ->
    @classList.add('atom-kdb-reference')
    container = document.createElement('div')
    @content = document.createElement('div')
    @close = document.createElement('button')
    @close.classList.add('btn', 'atom-kdb-reference-close')
    @close.innerHTML = 'Close'
    container.appendChild(@close)
    container.appendChild(@content)
    @appendChild(container)
    @itemsToUpdate = []

  initialize: (model) ->
    @setModel(model)
    this

  clickHandle: (i) ->
    @model.goToReference(i)

  buildItems: (data) ->
    @itemsToUpdate = []
    @content.innerHTML = ''
    headline = document.createElement 'h2'
    headline.innerHTML = data.name
    @content.appendChild(headline)
    list = document.createElement 'ul'
    for item, i in data.refs
      li = document.createElement 'li'
      liContainer = document.createElement 'h3'

      liSpan = document.createElement 'span'
      liPos = document.createElement 'span'
      liPos.classList.add 'darken'
      liPos.innerHTML = "(#{item.line}:#{item.col}):"
      liCont = document.createElement 'span'
      liCont.innerHTML = 'loading...'
      @itemsToUpdate.push item: item, htmlItem: liCont
      liSpan.appendChild liPos
      liSpan.appendChild liCont
      liContainer.appendChild liSpan

      liFile = document.createElement 'span'
      liFile.classList.add 'darken'
      liFile.innerHTML = "(#{item.file})"
      liContainer.appendChild liFile

      liDiv = document.createElement 'div'
      liDiv.classList.add 'clear'
      liContainer.appendChild liDiv

      li.appendChild liContainer
      li.addEventListener('click', @clickHandle.bind(this, i), false)
      list.appendChild(li)
    @content.appendChild(list)
    @requestFileInfo()

  requestFileInfo: ->
    return unless @itemsToUpdate.length>0
    v = @itemsToUpdate[0]
    f = new (require 'atom').File(v.item.file)
    debug "Request file: #{v.item.file}"
    done = (text) =>
      @updateItems(v.item.file, text)
      @requestFileInfo()
    err = (err) =>
     console.error "Autocomple-kdb: couldn't read file: #{v.item.file}"
     @updateItems v.item.file, ""
     @requestFileInfo()
    f.read(true).then done, err

  updateItems: (file, text) ->
    lines = text.split('\n')
    @itemsToUpdate = @itemsToUpdate.filter (i) ->
      return true unless file is i.item.file
      i.htmlItem.textContent = lines[i.item.line-1] || 'error'
      false

  destroy: ->
    @model = null
    @itemsToUpdate = []
    @remove()

  getClose: ->
    @close

  getModel: ->
    @model

  setModel: (model) ->
    @model = model

module.exports = document.registerElement('atom-kdb-reference', prototype: ReferenceView.prototype)
