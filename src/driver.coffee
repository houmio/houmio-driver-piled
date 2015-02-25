async = require 'async'
Bacon = require 'baconjs'
carrier = require 'carrier'
net = require 'net'
zerofill = require 'zerofill'
fs = require 'fs'

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
bridgeSocket = new net.Socket()

console.log "Using HOUMIO_BRIDGE=#{houmioBridge}"

exit = (msg) ->
  console.log msg
  process.exit 1

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

isWriteMessage = (message) -> message.command is "write"

createPiledLine = (message) ->
  brightness = message.data.bri/255
  "#{message.data.protocolAddress}=#{brightness}"


openBridgeMessageStream = (socket) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    messageStream.onEnd -> exit "Bridge stream ended, protocol: #{protocolName}"
    messageStream.onError (err) -> exit "Error from bridge stream, protocol: #{protocolName}, error: #{err}"
    writeMessageStream = messageStream.filter isWriteMessage
    cb null, writeMessageStream

openStreams = [ openBridgeMessageStream(bridgeSocket) ]

async.series openStreams, (err, [piledWriteMessages]) ->
  if err then exit err
  piledWriteMessages
    .map createPiledLine
    .onValue (m)->
      fs.writeFile '/dev/pi-blaster', m, (err) ->
        if err then console.log "Write Error", err
  bridgeSocket.write (JSON.stringify { command: "driverReady", protocol: "piled"}) + "\n"
