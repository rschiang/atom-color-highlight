_ = require 'underscore-plus'
{CompositeDisposable, Emitter} = require 'event-kit'
Color = require 'pigments'

module.exports =
class AtomColorHighlightModel

  @Color: Color

  @markerClass: 'color-highlight'
  @bufferRange: [[0,0], [Infinity,Infinity]]

  constructor: (@editor, @buffer) ->
    @dirty = false
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    try atom.packages.activatePackage('project-palette-finder').then (pack) =>
      finder = pack.mainModule
      @constructor.Color = Color = finder.Color if finder?
      @subscriptions.add finder.onDidUpdatePalette @update

    @constructor.Color = Color

  onDidUpdateMarkers: (callback) ->
    @emitter.on 'did-update-markers', callback

  update: =>
    return if @frameRequested

    @frameRequested = true
    requestAnimationFrame =>
      @frameRequested = false
      @updateMarkers()

  subscribeToBuffer: ->
    @subscriptions.add @editor.onDidChange => @dirty = true
    @subscriptions.add @editor.onDidStopChanging @update

  unsubscribeFromBuffer: ->
    @subscriptions.dispose()
    @buffer = null

  init: ->
    if @buffer?
      @subscribeToBuffer()
      @destroyAllMarkers()
      @update()

  dispose: ->
    @unsubscribeFromBuffer() if @buffer?

  eachColor: (block) ->
    return Color.scanBufferForColors(@buffer, block) if @buffer?

  updateMarkers: ->
    return @destroyAllMarkers() unless @buffer?
    return if @updating

    @updating = true
    updatedMarkers = []
    markersToRemoveById = {}

    markersToRemoveById[marker.id] = marker for marker in @markers

    try
      promise = @eachColor()

      promise.then (results) =>
        @updating = false
        results = [] unless results?

        for res in results
          {bufferRange: range, match, color} = res

          continue if color.isInvalid

          if marker = @findMarker(match, range)
            if marker.bufferMarker.properties.cssColor isnt color.toCSS()
              marker = @createMarker(match, color, range)
            else
              delete markersToRemoveById[marker.id]
          else
            marker = @createMarker(match, color, range)

          updatedMarkers.push marker

        marker.destroy() for id, marker of markersToRemoveById

        @markers = updatedMarkers
        @emitter.emit 'did-update-markers', _.clone(@markers)
        @dirty = false
      .fail (e) ->
        @dirty = false
        console.log e

    catch e
      @destroyAllMarkers()
      throw e

  findMarker: (color, range) ->
    attributes =
      type: @constructor.markerClass
      color: color
      startPosition: range.start
      endPosition: range.end

    _.find @editor.findMarkers(attributes), (marker) -> marker.isValid()

  destroyAllMarkers: ->
    marker.destroy() for marker in @markers ? []
    @markers = []
    @emitter.emit 'did-update-markers', _.clone(@markers)

  createMarker: (color, colorObject, range) ->
    l = colorObject.luma()

    textColor = if l > 0.43
      'black'
    else
      'white'

    markerAttributes =
      type: @constructor.markerClass
      color: color
      cssColor: colorObject.toCSS()
      textColor: textColor
      invalidate: 'touch'
      persistent: false

    @editor.markBufferRange(range, markerAttributes)
