assert = require "assert"
mocha = require "mocha"
_ = require "underscore"
thriftPool = {_private} = require "../lib/index"
async  = require 'async'
sinon = require "sinon"
{EventEmitter} = require "events"

connection_mock = ->
  connection = new EventEmitter()
  connection.connection =
    setKeepAlive: sinon.stub()
  connection.end = sinon.stub()
  connection

# thrift-pool tests that the exported package properly wraps
# generic-pool with a passed thrift object, service, and options.
describe "thrift-pool", ->

  # Initialize mocks to use in thrift-pool creation
  before ->
    @generic_error = new Error("error")
    @mock_connection = connection_mock()
    @thriftService =
      Client: class
        fn: ->
        fn2: ->
    @initialized_thrift_service =
      fn: sinon.stub().yields null, "xyz"
      fn2: sinon.stub().yields @generic_error, null
    @thrift =
      createConnection: =>
        setImmediate => @mock_connection.emit "connect"
        @mock_connection
      createClient: sinon.stub().returns @initialized_thrift_service
    @wrappedPool =
      thriftPool @thrift, @thriftService, {"host", "port"}

  afterEach ->
    @mock_connection.removeAllListeners() # Removes all event listeners

  it "returns an object with the original keys of the thrift service", ->
    assert @wrappedPool.fn
    assert.equal typeof @wrappedPool.fn, "function"
    assert.deepEqual _(@wrappedPool).keys(), ["fn", "fn2"]

  it "creates a client with connection from pool when calling a method", (done) ->
    @wrappedPool.fn "foo", "bar", (err, data) =>
      assert.equal @thrift.createClient.args[0][0], @thriftService
      assert.equal @thrift.createClient.args[0][1], @mock_connection
      assert @initialized_thrift_service.fn.calledWith "foo", "bar"
      done()

  it 'creates thrift connection with passed options', (done) ->
    thrift =
      createConnection: sinon.stub().returns @mock_connection
      createClient: sinon.stub().returns @initialized_thrift_service
    pool_options = {host: "host", port: "port"}
    thrift_options = {connect_timeout: 100, timeout: 200}
    setImmediate => @mock_connection.emit "connect"
    wrappedPool = thriftPool thrift, @thriftService, pool_options, thrift_options
    wrappedPool.fn "foo", (err, data) ->
      assert thrift.createConnection.calledWith pool_options.host, pool_options.port, thrift_options
      done()

  it 'returns expected results when called with service functions', (done) ->
    async.series [
      (cb) =>
        @wrappedPool.fn "foo", (err, data) ->
          assert.equal data, "xyz"
          cb()
      (cb) =>
        @wrappedPool.fn2 "foo", (err, data) =>
          assert.deepEqual err, @generic_error
          assert.equal null, data
          cb()
    ], ->
      done()

  it 'returns an error if connection errors as it is initialized', (done) ->
    connection_error = new Error "Connection error"
    thrift =
      createConnection: =>
        setImmediate => @mock_connection.emit "error", connection_error
        @mock_connection
      createClient: =>
        createClient: sinon.stub().returns @initialized_thrift_service
    wrappedPool =
      thriftPool thrift, @thriftService, {"host", "port"}
    async.series [
      (cb) ->
        wrappedPool.fn "foo", (err, data) ->
          assert.deepEqual err, connection_error
          assert.equal null, data
          cb()
      (cb) ->
        wrappedPool.fn2 "foo", (err, data) ->
          assert.deepEqual err, connection_error
          assert.equal null, data
          cb()
    ], ->
      done()

  it 'returns an error if connection errors during client callback', (done) ->
    internal_error = new Error("Internal error")
    initialized_thrift_service =
      fn: (arg, cb) =>
        setImmediate => @mock_connection.emit "error", internal_error
        wait = -> cb null, arg
        setTimeout wait, 1000
    thrift =
      createConnection: =>
        setImmediate => @mock_connection.emit "connect"
        @mock_connection
      createClient: sinon.stub().returns initialized_thrift_service
    wrappedPool = thriftPool thrift, @thriftService, {"host", "port"}
    wrappedPool.fn "abc", (err, data) ->
      assert.deepEqual err, internal_error
      assert.equal data, null
      done()

  it 'returns an error if connection timeouts during client callback', (done) ->
    connection_timeout_error = new Error _private.TIMEOUT_MESSAGE
    initialized_thrift_service =
      fn: (arg, cb) =>
        setImmediate => @mock_connection.emit "timeout"
        wait = -> cb null, arg
        setTimeout wait, 1000
    thrift =
      createConnection: =>
        setImmediate => @mock_connection.emit "connect"
        @mock_connection
      createClient: sinon.stub().returns initialized_thrift_service
    wrappedPool = thriftPool thrift, @thriftService, {"host", "port"}, {timeout: 100}
    wrappedPool.fn "abc", (err, data) ->
      assert.deepEqual err, connection_timeout_error
      assert.equal data, null
      done()

  it 'returns an error if connection is closed during client callback', (done) ->
    connection_close_error = new Error _private.CLOSE_MESSAGE
    initialized_thrift_service =
      fn: (arg, cb) =>
        setImmediate => @mock_connection.emit "close"
        wait = -> cb null, arg
        setTimeout wait, 1000
    thrift =
      createConnection: =>
        setImmediate => @mock_connection.emit "connect"
        @mock_connection
      createClient: sinon.stub().returns initialized_thrift_service
    wrappedPool = thriftPool thrift, @thriftService, {"host", "port"}, {timeout: 100}
    wrappedPool.fn "abc", (err, data) ->
      assert.deepEqual err, connection_close_error
      assert.equal data, null
      done()


# Create_pool unit makes sure create_pool properly initializes a generic-pool
# for thrift. Each of these tests creates a new pool which uses a single mock
# connection (generic_pool handles and tests all other pooling functions).
#
# The following is tested:
#   - "create", "destroy", and "validate" functions are initialized properly
#     and behave as expected.
#   - Emitting thrift events - "connect", "error", and "close", yield proper
#     behavior for a connection when it is in a pool, being created, or acquired.
#   - Passing "timeout" in thrift_options adds "timeout" listener and behaves
#     as expected.
describe 'create_pool unit', ->
  # Initialize mocks to use in pool creation
  before ->
    @mock_connection = connection_mock()
    @thrift =
      createConnection: sinon.stub().returns @mock_connection
    @options =
      host: "host"
      port: "port"
      max_connections: 20
      min_connections: 0
      idle_timeout: 30000

  # Function helpers
  before ->
    # Makes sure err and connection match that of a successful acquire.
    @assert_valid = (err, connection) ->
      assert.ifError err
      assert.notEqual connection, null
      assert.equal connection.__ended, false

    # Makes sure that calling acquire on connection destroys
    # that connection and creates and returns another one.
    @acquire_destroys = (pool, cb) ->
      setImmediate => @mock_connection.emit "connect"
      pool.acquire (err, connection) =>
        @assert_valid err, connection
        assert @mock_connection.end.called
        assert @thrift.createConnection.called
        pool.release connection
        cb()

  afterEach ->
    @mock_connection.removeAllListeners() # Removes all event listeners

  # Tests "create" function, with "connect" event
  # as connection goes from create -> acquire.
  it 'properly creates a connection when there is no error', (done) ->
    @thrift.createConnection.reset()
    pool = _private.create_pool @thrift, @options
    setImmediate => @mock_connection.emit "connect"
    pool.acquire (err, connection) =>
      @assert_valid err, connection
      assert @thrift.createConnection.called
      assert.equal pool.getPoolSize(), 1
      assert.equal pool.availableObjectsCount(), 0
      pool.release connection
      done()

  # Tests "create" function, with "error" event
  # as connection goes from create -> acquire.
  it 'returns an error to acquire if error emits during connection creation', (done) ->
    @thrift.createConnection.reset()
    connection_error = new Error "Connection error"
    pool = _private.create_pool @thrift, @options
    setImmediate => @mock_connection.emit "error", connection_error
    pool.acquire (err, connection) =>
      assert.deepEqual err, connection_error
      assert.equal connection, null
      assert @thrift.createConnection.called
      assert.equal pool.getPoolSize(), 0
      assert.equal pool.availableObjectsCount(), 0
      done()

  # Tests "create" function, with "close" event
  # as connection goes from create -> acquire.
  it 'returns an error to acquire if close emits during connection creation', (done) ->
    @thrift.createConnection.reset()
    close_error = new Error _private.CLOSE_MESSAGE
    pool = _private.create_pool @thrift, @options
    setImmediate => @mock_connection.emit "close", close_error
    pool.acquire (err, connection) =>
      assert.deepEqual err, close_error
      assert.equal connection, null
      assert @thrift.createConnection.called
      assert.equal pool.getPoolSize(), 0
      assert.equal pool.availableObjectsCount(), 0
      done()

  # Tests "create" function, with "timeout" event and timeout in thrift options
  # as connection goes from create -> acquire.
  it 'returns an error to acquire if timeout emits during connection creation', (done) ->
    @thrift.createConnection.reset()
    timeout_error = new Error _private.TIMEOUT_MESSAGE
    pool = _private.create_pool @thrift, @options, {timeout: 10}
    setImmediate => @mock_connection.emit "timeout", timeout_error
    pool.acquire (err, connection) =>
      assert.deepEqual err, timeout_error
      assert.equal connection, null
      assert @thrift.createConnection.called
      assert.equal pool.getPoolSize(), 0
      assert.equal pool.availableObjectsCount(), 0
      done()

  # Tests "destroy" function, note that connection can
  # only be manually destroyed after it is acquired.
  it 'properly destroys a connection', (done) ->
    @mock_connection.end.reset()
    pool = _private.create_pool @thrift, @options
    setImmediate => @mock_connection.emit "connect"
    pool.acquire (err, connection) =>
      @assert_valid err, connection
      pool.destroy connection # Destroy is called as an alternative to release
      assert @mock_connection.end.called
      assert.equal pool.getPoolSize(), 0
      done()

  # Tests "validate" function as connection moves from pool -> acquire.
  # Two cases:
  #   - connection is valid, it is returned
  #   - connection is not valid, it is destroyed, new connection is returned.
  it 'properly validates a connection', (done) ->
    pool = _private.create_pool @thrift, _.extend {ttl: 100}, @options
    async.series [
      (cb) =>
        # Connection is valid and is released
        @mock_connection.end.reset()
        setImmediate => @mock_connection.emit "connect"
        @thrift.createConnection.reset()
        @mock_connection.__reap_time = Date.now() - 1
        pool.acquire (err, connection) =>
          @assert_valid err, connection
          assert.equal @mock_connection.end.called, false
          pool.release connection
          cb()
      (cb) =>
        # Connection is invalid due to TTL and is destroyed and a
        # new connection is created and returned
        @mock_connection.end.reset()
        setImmediate => @mock_connection.emit "connect"
        @thrift.createConnection.reset()
        @mock_connection.__reap_time = Date.now() + 1
        assert.equal pool.getPoolSize(), 1
        assert.equal pool.availableObjectsCount(), 1
        @acquire_destroys pool, cb
      (cb) =>
        # Connection in pool is marked invalid, destroyed, and a
        # new connection is created and returned
        @mock_connection.end.reset()
        @thrift.createConnection.reset()
        assert.equal pool.getPoolSize(), 1
        assert.equal pool.availableObjectsCount(), 1
        @mock_connection.__ended = true # Mark connection as invalid
        @acquire_destroys pool, cb
    ], ->
      done()

  before ->
    # Emits a connect event, acquires, and releases the connection.
    @connect_release = (pool, cb) =>
      # Connection succeeds in creation and is released
      setImmediate => @mock_connection.emit "connect"
      pool.acquire (err, connection) =>
        @assert_valid err, connection
        pool.release connection
        cb()

    # Used to test the event emitters that invalidate a connection.
    # Flow: creates/releases connection -> emits emit_fn -> acquires connection.
    @emit_invalidates_connection = (emit_fn, done, thrift_options = {}) =>
      pool = _private.create_pool @thrift, @options, thrift_options
      async.series [
        (cb) =>
          @connect_release pool, cb
        (cb) =>
          # Call emit function when connection is in pool
          @mock_connection.end.reset()
          @thrift.createConnection.reset()
          emit_fn @mock_connection
          wait = -> cb()
          setTimeout wait, 1000
        (cb) =>
          # Connection in pool should be marked invalid, destroyed,
          # and a new connection is created and returned
          assert.equal pool.getPoolSize(), 1
          assert.equal pool.availableObjectsCount(), 1
          @acquire_destroys pool, cb
      ], ->
        done()

  # Tests "error" event as connection goes from pool -> acquire.
  it "invalidates a connection in a pool when connection emits error", (done) ->
    emit_fn = (connection) ->
      connection_error = new Error "Connection error"
      setImmediate -> connection.emit "error", connection_error
    @emit_invalidates_connection emit_fn, done

  # Tests "close" event as connection goes from pool -> acquire.
  it "invalidates a connection in a pool when connection emits close ", (done) ->
    emit_fn = (connection) ->
      setImmediate -> connection.emit "close"
    @emit_invalidates_connection emit_fn, done

  # Tests "timeout" event as connection goes from pool -> acquire.
  # Makes sure that event only emits when timeout is passed.
  it "invalidates a connection in the pool when connection emits timeout", (done) ->
    emit_fn = (connection) ->
      setImmediate -> connection.emit "timeout"
    @emit_invalidates_connection emit_fn, done, {timeout: 200}

  it "does not invalidate connection for 'timeout' if no timeout passed", (done) ->
    pool = _private.create_pool @thrift, @options, {option: 200}
    async.series [
      (cb) =>
        @connect_release pool, cb
      (cb) =>
        @mock_connection.end.reset()
        @thrift.createConnection.reset()
        setImmediate => @mock_connection.emit "timeout"
        wait = -> cb()
        setTimeout wait, 1000
      (cb) =>
        # Connection in pool should be retrieved, and connection
        # should not have been destroyed
        assert.equal pool.getPoolSize(), 1
        assert.equal pool.availableObjectsCount(), 1
        setImmediate => @mock_connection.emit "connect"
        pool.acquire (err, connection) =>
          @assert_valid err, connection
          assert.equal @mock_connection.end.called, false
          assert.equal @thrift.createConnection.called, false
          pool.release connection
          cb()
    ], ->
      done()
