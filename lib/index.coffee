_ = require "underscore"
async = require "async"
genericPool = require "generic-pool"

module.exports = (thrift, service, options={}) ->

  throw new Error "You must specify #{key}" for key in ["host", "port"] when not options[key]

  options = _(options).defaults
    timeout: 250 # Timeout (in ms) for thrift.createConnection
    max_connections: 20 # Max number of connections to keep open
    min_connections: 2 # Min number of connections to keep open
    idle_timeout: 2000 # Time (in ms) to wait until closing idle connections

  pool = genericPool.Pool(
    name: "thrift"
    create: (cb) ->
      connection = thrift.createConnection(options.host, options.port, {timeout: options.timeout})
      connection.__ended = false
      connection.on "connect", ->
        connection.connection.setKeepAlive(true)
        cb null, connection
      connection.on "close", ->
        connection.__ended = true
      connection.on "error", (err) ->
        connection.__ended = true
        cb(err)
    destroy: (connection) -> connection.end()
    validate: (connection) -> not connection.__ended
    max: options.max_connections
    min: options.min_connections
    idleTimeoutMillis: options.idle_timeout
  )

  wrap_thrift_fn = (fn) -> (args..., cb) ->
    async.auto
      connection: (cb_a) -> pool.acquire cb_a
      returned_data: ['connection'].concat (cb_a, {connection}) ->
        client = thrift.createClient(service, connection)
        client[fn] args..., (returned_data...) -> cb_a(null, returned_data)
    , (err, {returned_data, connection}) ->
      return cb(err) if err
      pool.release(connection) if connection
      cb returned_data...

  _(service.Client.prototype).chain().keys().map((fn_name) ->
    [fn_name, wrap_thrift_fn(fn_name)]
  ).object().value()
