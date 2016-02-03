Player = require 'player'
nature_sound = new Player 'mountain-stream1.mp3'
bell_sound = new Player 'bell.mp3'

Hue = require 'node-hue-api'

Hue.USERNAME = '655bb058d43b072b29a4d13dbfd833'
Hue.USER_DESCTIPTION = 'aitc-nui-20160204'
Hue.MIN_BRIGHTNESS = 1
Hue.MAX_BRIGHTNESS = 254
Hue.MIN_HUE = 0
Hue.MAX_HUE = 65536
Hue.MIN_SATURATION = 0
Hue.MAX_SATURATION = 254
Hue.SEARCHING_TIMEOUT = 10 * 1000

LIGHT_BEDROOM = 2

ENTRY_POINT = 'http://aitc2.dyndns.org/openmasami/record'
WAKEUP_TIME = "#{ENTRY_POINT}/latest/bedroom/person1/wakeupTime"
SLEEPING_DEPTH = "#{ENTRY_POINT}/latest/bedroom/person1/sleepLevel"
PERSON_EXISTS = "#{ENTRY_POINT}/latest/bedroom/person1/exist"

SLEEP_DEPTH_FOR_WAKEUP = 2
MILLIS_BEFORE_WAKEUP = 30 * 60 * 1000

INTERVAL_MILLIS = 500


request = require 'request'

watch = (url, action)->
  previous = undefined
  console.log 'Starting watch:', url
  watchdog = ->
    request url, (error, response, body)->
      data = JSON.parse body
      #console.log url, body
      if data.length > 0
        value = data[0] || 0
        if value != previous
          action value, previous
          previous = value
    setTimeout watchdog, INTERVAL_MILLIS
  watchdog()

class Alarm
  constructor: (@hue)->
    @statuses =
      wakeupTime: ''
      sleepingDepth: 0
      isExists: false

    self = @
    watch WAKEUP_TIME, (value)->
      now = new Date()
      datetime = "#{now.getFullYear()}/#{now.getMonth() + 1}/#{now.getDate()} #{value}"
      console.log 'wakeupTime =', datetime
      self.update wakeupTime: (Date.parse datetime)

    watch SLEEPING_DEPTH, (value)->
      self.update sleepingDepth: (parseInt value)

    watch PERSON_EXISTS, (value)->
      self.update isExists: (value == '1')

    setInterval (-> self.check()), INTERVAL_MILLIS

  update: (newStatuses)->
    console.log 'update:', newStatuses
    for key, value of newStatuses
      @statuses[key] = value

  check: ->
    now = Date.now()

    if !@statuses.isExists
      @stop light: off
    else if !@statuses.wakeupTime or @statuses.sleepingDepth == 0
      @stop light: on
    else if now >= @statuses.wakeupTime
      @wakeup sound: bell_sound, light: 'alert'
    else if @statuses.sleepingDepth <= SLEEP_DEPTH_FOR_WAKEUP and
      now >= @statuses.wakeupTime - MILLIS_BEFORE_WAKEUP
        @wakeup sound: nature_sound, light: 'dim'
    else
      @stop light: off

    @

  config: (settings)->
    @hue = settings.hue if settings.hue
    @update {}

  wakeup: (params)->
    console.log 'WAKEUP!!!'
    unless @player == params.sound
      console.log 'play:', params.sound._list[0].src
      @player?.stop()
      @player = params.sound.play()
      .on 'error', (error)->
        console.log error
        params.sound.play()
    @setLight params.light if @hue
    @

  stop: (params)->
    if @player
      console.log 'STOP'
      @player.stop()
      delete @player
    @setLight params.light if @hue
    @

  setLight: (scene)->
    if @hue and  @light != scene
      @light = scene
      console.log 'light:', scene

      state = Hue.lightState.create()
        .on()
        .brightness 50
        .transitionInstant()
        .effect 'none'
        .alert 'none'

      switch scene
        when on
          state.colorTemp 200
        when off
          state.off()
            .transitionSlow()
        when 'alert'
          state.longAlert()
            .colorLoop()
            .brightness 100
        when 'dim'
          state.white 500, 10
            .transition 5 * 1000
      hue = @hue
      hue.setLightState LIGHT_BEDROOM, state, ->
        hue.lightStatus LIGHT_BEDROOM, (error, result)-> console.log result
    @

alarm = new Alarm

Hue.upnpSearch Hue.SEARCHING_TIMEOUT
  .then (bridges)->
    console.log 'Hue Bridges Found:', bridges
    for bridge in bridges
      if bridge
        api = new Hue.HueApi bridge.ipaddress, Hue.USERNAME
        api.getConfig -> console.log 'Hue config:', arguments
        alarm.config hue: api
  .done()
