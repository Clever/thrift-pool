assert = require "assert"
mocha = require "mocha"
_ = require "underscore"
thrift_pool = {_private} = require "../lib/index"
async  = require 'async'
thrift = require "thrift"

#To-do: mock out thrift so tests can be run without local thrift instances
describe 'create_pool unit', ->
  before ->
    @options =
      host: "localhost"
      port: 9090
      timeout: 250 # Timeout (in ms) for thrift.createConnection
      max_connections: 20 # Max number of connections to keep open
      min_connections: 0 # Min number of connections to keep open
      idle_timeout: 2000 # Time (in ms) to wait until closing idle connections
    @pool = _private.create_pool thrift, @options

  it 'creates a connection when the pool is empty', (done) ->
    assert.equal @pool.getPoolSize(), 0
    assert.equal @pool.availableObjectsCount(), 0
    @pool.acquire (err, connection) =>
      assert.ifError err
      assert.equal connection.__ended, false
      @pool.release connection
      done()

  it 'properly destroys a connection', (done) ->
    @pool.acquire (err, connection) =>
      assert.ifError err
      assert.equal connection.__ended, false
      prevPoolSize = @pool.getPoolSize()
      @pool.release connection
      @pool.destroy connection
      # Connection should be ended, and pool size should have 1 less
      assert.equal connection.__ended, true
      assert.equal prevPoolSize-1, @pool.getPoolSize()
      done()

  it 'properly releases a connection', (done) ->
    prevPoolSize = @pool.getPoolSize()
    prevAvailObjects = @pool.availableObjectsCount()
    @pool.acquire (err, connection) =>
      assert.ifError err
      if prevAvailObjects > 0
        # Should have one less available object
        assert.equal @pool.availableObjectsCount(), prevAvailObjects-1
        @pool.release connection
        # After releasing connection should have same number of connections again
        assert.equal @pool.availableObjectsCount(), prevAvailObjects
        done()
      else
        # New connection must have been made and pool size is now larger
        assert.equal @pool.getPoolSize(), prevPoolSize+1
        # After releasing connection should have additional available object
        @pool.release connection
        assert.equal @pool.availableObjectsCount(), prevAvailObjects+1
        done()

  it 'gives you a new connection if a connection is acquired but not released', (done) ->
    prevPoolSize = prevAvailObjects = 0
    async.series [
      (cb) =>
        @pool.acquire (err) =>
          assert.ifError err
          prevPoolSize = @pool.getPoolSize()
          prevAvailObjects = @pool.availableObjectsCount()
          cb(null)
      (cb) =>
        @pool.acquire (err) =>
          assert.ifError err
          # Two cases:
          #   a) Available connection decreases by 1, pool size stays the same
          #   b) No available connections, pool size increases by 1, 
          #      and available connections stay the same
          if prevAvailObjects - @pool.availableObjectsCount() is 1
            assert.equal prevPoolSize, @pool.getPoolSize()
            cb(null)
          else
            assert.equal prevAvailObjects, @pool.availableObjectsCount()
            assert.equal prevPoolSize + 1, @pool.getPoolSize()
            cb(null)
    ], (err) ->
      assert.ifError err
      done()

  it 'gives you the same connection if it has been acquired and released', (done) ->
    prevPoolSize = prevAvailObjects = 0
    async.series [
      (cb) =>
        @pool.acquire (err, connection) =>
          assert.ifError err
          prevPoolSize = @pool.getPoolSize()
          prevAvailObjects = @pool.availableObjectsCount()
          @pool.release connection
          # Pool size should be same size, avail. objects should increase by 1
          assert.equal prevPoolSize, @pool.getPoolSize()
          assert.equal prevAvailObjects, @pool.availableObjectsCount() - 1
          cb(null)
      (cb) =>
        @pool.acquire (err, connection) =>
          assert.ifError err
          # PoolSize and object count should match prev
          assert.equal prevPoolSize, @pool.getPoolSize()
          assert.equal prevAvailObjects, @pool.availableObjectsCount()
          cb(null)
    ], (err) ->
      assert.ifError err
      done()

# To-do: Integration testing, with service mock
describe 'thrift-pool integration', ->
  it 'works', (done) ->
    done()
