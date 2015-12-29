# Thrift Pool

A module that wraps thrift interfaces in connection pooling logic to make them more resilient.

The [node thrift code](https://www.npmjs.com/package/thrift) exposes a `service` and `types` file.
The node thrift client also exposes interfaces to create connections to the thrift server.
There is no way to use the node thrift library to do connection pooling or to create new connections if existing connections fail.

This library takes in a thrift `service` and wraps the methods with connection pooling logic (based on [node-pool](https://github.com/coopernurse/node-pool)).


## Installation

```
npm install node-thrift-pool
```

## Usage
```javascript
var thrift = require('thrift'),
  Service = require('./gen-nodejs/Service'),
  Types = require('./gen-nodejs/types'),
  thriftPool = require('node-thrift-pool');

var thrift_client = thriftPool(thrift, Service, {host: "localhost", port: 9090});

/*
 * thrift_client is now an initialized thrift client that uses connection pooling behind the scenes
 * thrift_client.method(function(err, returned_data){console.log(err, returned_data)});
 */

```

## Supported pooling options
Options to use when creating pool, defaults match those used by node-pool.

- `host` - **Required** - The host of the thrift server to connect to
- `port` - **Required** - The port of the thrift server to connect to
- `log` - Default: `false` - true/false or function
- `max_connections` - Default: `1` - Max number of connections to keep open at any given time
- `min_connections` - Default: `0` - Min number of connections to keep open at any given time
- `idle_timeout` - Default: `30000` - Time (ms) to wait until closing idle connections
- `ssl` - Default: undefined - If the option is passed SSL/TLS connection will be used.

## Thrift options - optional
All thrift options are supported and can be passed in as an object in addition to the pooling options.

```javascript
var thrift_options = {
    timeout: 250
};
var thrift_client = thriftPool(thrift, Service, {host: "localhost", port: 9090}, thrift_options);

```

**Note:**  If the `timeout` option is passed in the thrift_options object, a `timeout` listener will be added to the connection.
  - If the `timeout` event is emitted on a connection while it is in the pool, the connection will be invalidated and treated the same way as if an `error` or `close` event had been emitted.
  - If the `timeout` event is emitted after the connection is acquired a timeout error will be returned: `new Error "Connection timeout"`.

## Development
After making any changes, please add or run any required tests. Tests are located in the `test` directory, and can be run via npm:
```
npm test
```

- The [debug](https://github.com/visionmedia/debug) package is used to simplify debugging.  To turn on logging: `export DEBUG=thrift-pool`
- Source hosted at [GitHub](https://github.com/Clever/thrift-pool)
- Report issues, questions, feature requests on [GitHub Issues](https://github.com/Clever/thrift-pool/issues)

Pull requests are welcome! Please ensure your patches are well tested. Please create separate branches for separate features/patches.
