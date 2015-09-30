Provider = require './provider'
Reference = require './reference'
{CompositeDisposable} = require 'atom'

module.exports = AutocompleteKdbQ =
  subscriptions: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable()
    @provider = new Provider()
    @reference = new Reference(@provider)
    @registerEvents()

  deactivate: ->
    @subscriptions.dispose()
    @provider.dispose()
    @reference.destroy()
    @provider = null
    @reference = null

  serialize: ->
    null

  provide: ->
    @provider

  provideLinter: ->
    @provider

  registerEvents: ->
    @subscriptions.add atom.commands.add 'atom-text-editor', 'kdb-q:references': (event) =>
      @reference.findReference() if @reference
    @subscriptions.add atom.commands.add 'atom-text-editor', 'kdb-q:definition': (event) =>
      @reference.goToDefinition() if @reference
    @subscriptions.add atom.commands.add 'atom-text-editor', 'kdb-q:doc': (event) =>
      @reference.showDoc() if @reference
