_ = require "underscore"
_.mixin require "underscore.deep"
async = require "async"
genericPool = require "generic-pool"
debug = require("debug")("thrift-pool")

TIMEOUT_MESSAGE = "Thrift-pool: Connection timeout"
CLOSE_MESSAGE = "Thrift-pool: Connection closed"

# create_cb creates and initializes a connection
#  @param thrift, used to create connection
#  @param pool_options, host and port used to create connection
#  @param thrift_options, passed to thrift connection,
create_cb = (thrift, pool_options, thrift_options, cb) ->
  cb = _.once cb

  pool_options.ssl ?= false
  if pool_options.ssl
    connection = thrift.createSSLConnection pool_options.host, pool_options.port, thrift_options
  else
    connection = thrift.createConnection pool_options.host, pool_options.port, thrift_options

  connection.__ended = false
  if pool_options.ttl?
    connection.__reap_time = Date.now() + _.random (pool_options.ttl / 2), (pool_options.ttl * 1.5)

  connection.on "connect", ->
    debug "in connect callback"
    connection.connection.setKeepAlive(true)
    cb null, connection
  connection.on "error", (err) ->
    debug "in error callback"
    connection.__ended = true
    cb err
  connection.on "close", ->
    debug "in close callback"
    connection.__ended = true
    cb new Error CLOSE_MESSAGE
  # timeout listener only applies if timeout is passed into thrift_options
  if thrift_options.timeout?
    debug "adding timeout listener"
    connection.on "timeout", ->
      debug "in timeout callback"
      connection.__ended = true
      cb new Error TIMEOUT_MESSAGE

# create_pool initializes a generic-pool
#   @param thrift library to use to in create_cb
#   @param pool_options, host/port are used in create_cb
#          max, min, idleTimeouts are used by generic pool
#   @param thrift_options used in create_cb
create_pool = (thrift, pool_options = {}, thrift_options = {}) ->
  pool = genericPool.Pool
    name: "thrift"
    create: (cb) ->
      create_cb thrift, pool_options, thrift_options, cb
    destroy: (connection) ->
      debug "in destroy"
      connection.end()
    validate: (connection) ->
      debug "in validate"
      return false if connection.__ended
      return true unless pool_options.ttl?
      connection.__reap_time > Date.now()
    log: pool_options.log
    max: pool_options.max_connections
    min: pool_options.min_connections
    idleTimeoutMillis: pool_options.idle_timeout

module.exports = (thrift, service, pool_options = {}, thrift_options = {}) ->

  throw new Error "Thrift-pool: You must specify #{key}" for key in ["host", "port"] when not pool_options[key]

  pool_options = _(pool_options).defaults
    log: false # true/false or function
    max_connections: 1 # Max number of connections to keep open at any given time
    min_connections: 0 # Min number of connections to keep open at any given time
    idle_timeout: 30000 # Time (ms) to wait until closing idle connections

  pool = create_pool thrift, pool_options, thrift_options

  # add_listeners adds listeners for error, close, and timeout
  #   @param connection, connection to add listeners to
  #   @param cb_error, callback to attach to "error" listener
  #   @param cb_timeout, callback to attach to "timeout" listener
  #   @param cb_close, callback to attach to "close" listener
  add_listeners = (connection, cb_error, cb_timeout, cb_close) ->
    connection.on "error", cb_error
    connection.on "close", cb_close
    if thrift_options.timeout?
      connection.on "timeout", cb_timeout

  # remove_listeners removes error, timeout, and close listeners with given callbacks
  #   @param connection, connection to remove listeners from
  #   @param cb_error, error callback to remove from "error" listener
  #   @param cb_timeout, timeout callback to remove from "timeout" listener
  #   @param cb_close, close callback to remove from "close" listener
  remove_listeners = (connection, cb_error, cb_timeout, cb_close) ->
    connection.removeListener "error", cb_error
    connection.removeListener "close", cb_close
    if thrift_options.timeout?
      connection.removeListener "timeout", cb_timeout

  # wrap_thrift_fn when called with a function and arguments/callback:
  #   - acquires a connection
  #   - adds additional connection event listeners
  #   - creates a client with the acquired connection
  #   - calls client with fn and passed args and callback
  #   - connection is released before results are returned
  #  @return, function that takes in arguments and a callback
  wrap_thrift_fn = (fn) -> (args..., cb) ->
    pool.acquire (err, connection) ->
      debug "Connection acquired"
      debug {err}
      debug {connection}
      return cb err if err?
      cb = _.once cb
      cb_error = (err) ->
        debug "in error callback, post-acquire listener"
        cb err
      cb_timeout = ->
        debug "in timeout callback, post-acquire listener"
        cb new Error TIMEOUT_MESSAGE
      cb_close = ->
        debug "in close callback, post-acquire listener"
        cb new Error CLOSE_MESSAGE
      add_listeners connection, cb_error, cb_timeout, cb_close
      client = thrift.createClient service, connection
      debug "Client created"
      debug {client}
      client[fn] args..., (err, results...) ->
        debug "In client callback"
        remove_listeners connection, cb_error, cb_timeout, cb_close
        pool.release connection
        cb err, results...

  # The following returns a new object with all of the keys of an
  # initialized client class.
  # Note: _.mapValues only supports "simple", "vanilla" objects that
  # are not associated with a class.  Since service.Client.prototype
  # does not fall into that category, need to call _.clone first
  _.mapValues _.clone(service.Client.prototype), (fn, name) ->
    wrap_thrift_fn name

# For unit testing
_.extend module.exports, _private: {create_pool, TIMEOUT_MESSAGE, CLOSE_MESSAGE}
