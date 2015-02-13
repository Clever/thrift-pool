_ = require "underscore"
_.mixin require 'underscore.deep'
async = require "async"
genericPool = require "generic-pool"

# create_cb creates and initializes a connection
#  @param thrift, used to create connection
#  @param pool_options, host and port used to create connection
#  @param thrift_options, passed to thrift connection,
#
create_cb = (thrift, pool_options, thrift_options, cb) ->
  cb = _.once cb
  connection = thrift.createConnection pool_options.host, pool_options.port, thrift_options
  connection.__ended = false
  connection.on "connect", ->
    # console.log "in create connect"
    connection.connection.setKeepAlive(true)
    cb null, connection
  connection.on "error", (err) ->
    # console.log "in create error"
    connection.__ended = true
    cb err

  # "close" can only be called after "connect" event
  connection.on "close", ->
    # console.log "in create close"
    connection.__ended = true

  # timeout listener only applies if timeout is passed into thrift_options
  # if "timeout" emits, it sets the connection as ended
  if thrift_options.timeout?
    # console.log "adding timeout option"
    connection.on "timeout", ->
      # console.log "in create timeout"
      connection.__ended = true


# create_pool initializes a generic-pool
#   @param thrift library to use to in create_cb
#   @param pool_options, host/port are used in create_cb
#          max, min, idleTimeouts are used by generic pool
#   @param thrift_options used in create_cb
#
create_pool = (thrift, pool_options = {}, thrift_options = {}) ->
  pool = genericPool.Pool
    name: "thrift"
    create: (cb) ->
      create_cb thrift, pool_options, thrift_options, cb
    destroy: (connection) ->
      # console.log "in destroy"
      connection.end()
    validate: (connection) ->
      # console.log "in validate"
      not connection.__ended
    max: pool_options.max_connections
    min: pool_options.min_connections
    idleTimeoutMillis: pool_options.idle_timeout

module.exports = (thrift, service, pool_options = {}, thrift_options = {}) ->

  throw new Error "You must specify #{key}" for key in ["host", "port"] when not pool_options[key]

  pool_options = _(pool_options).defaults
    max_connections: 2 # Max number of connections to keep open
    min_connections: 0 # Min number of connections to keep open
    idle_timeout: 30000 # Time (in ms) to wait until closing idle connections

  pool = create_pool thrift, pool_options, thrift_options

  add_listeners = (connection, cb_error, cb_timeout) ->
    connection.on "error", cb_error
    if thrift_options.timeout?
      connection.on "timeout", cb_timeout

  remove_listeners = (connection, cb_error, cb_timeout) ->
    connection.removeListener 'error', cb_error
    if thrift_options.timeout?
      connection.removeListener 'timeout', cb_timeout

  wrap_thrift_fn = (fn) -> (args..., cb) ->
    pool.acquire (err, connection) ->
      return cb err if err?
      cb = _.once cb
      cb_error = (err) ->
        # console.log "in cb_error listener"
        cb err
      cb_timeout = ->
        # console.log "in cb_timeout listener"
        cb new Error "Connection timeout"
      add_listeners connection, cb_error, cb_timeout
      client = thrift.createClient service, connection
      client[fn] args..., (err, results...) ->
        remove_listeners connection, cb_error, cb_timeout
        pool.release connection
        cb err, results...

  # The following returns a new object with all of the keys of an
  # initialized client class.
  # Note: _.mapValues only supports "simple", "vanilla" objects that*
  # are not associated with a class.  Since service.Client.prototype
  # does not fall into that category, need to call _.clone first
  _.mapValues _.clone(service.Client.prototype), (fn, name) ->
    wrap_thrift_fn name

# For unit testing
_.extend module.exports, _private: {create_pool}
