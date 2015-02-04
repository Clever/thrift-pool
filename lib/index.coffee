_ = require "underscore"
async = require "async"
genericPool = require "generic-pool"

create_pool = (thrift, options) ->
  genericPool.Pool(
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
    destroy: (connection) ->
      # connection.end() calls end() on a net stream, but doesn't set ended to true
      connection.connection.end()
      connection.__ended = true
    validate: (connection) -> not connection.__ended
    max: options.max_connections
    min: options.min_connections
    idleTimeoutMillis: options.idle_timeout
  )

module.exports = (thrift, service, options={}) ->

  throw new Error "You must specify #{key}" for key in ["host", "port"] when not options[key]

  options = _(options).defaults
    timeout: 250 # Timeout (in ms) for thrift.createConnection
    max_connections: 20 # Max number of connections to keep open
    min_connections: 2 # Min number of connections to keep open
    idle_timeout: 2000 # Time (in ms) to wait until closing idle connections

  pool = create_pool thrift, options

  wrap_thrift_fn = (fn) -> (args..., cb) ->
    pool.acquire (err, connection) ->
      return cb err if err?
      client = thrift.createClient service, connection
      client[fn] args..., (err, results...) ->
        pool.release connection
        cb err, results...

  _(service.Client.prototype).chain().keys().map((fn_name) ->
    [fn_name, wrap_thrift_fn(fn_name)]
  ).object().value()

# For unit testing
_.extend module.exports, _private: {create_pool}
