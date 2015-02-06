# Thrift Pool

A module that wraps thrift interfaces in connection pooling logic to make them more resilient.

The [node thrift code](https://www.npmjs.com/package/thrift) exposes a `service` and `types` file.
The node thrift client also exposes interfaces to create connections to the thrift server.
There is no way to use the node thrift library to do connectionn pooling or to create new connections if existing connections fail.

This library takes in a thrift `service` and wraps the methods with connection pooling logic (based on [node-pool](https://github.com/coopernurse/node-pool)).


## Installation

```
npm install thrift-pool
```

## Usage
```javascript
var thrift = require('thrift'),
  Service = require('./gen-nodejs/Service'),
  Types = require('./gen-nodejs/types'),
  thriftPool = require('thrift-pool');

var thrift_client = thriftPool(thrift, Service, {host: "localhost", port: 9090});

/*
 * thrift_client is now an initialized thrift client that uses connection pooling behind the scenes
 * thrift_client.method(function(err, returned_data){console.log(err, returned_data)});
 */

```

## Supported options

- `host` - **Required** - The host of the thrift server to connect to
- `port` - **Required** - The port of the thrift server to connect to
- `timeout` - Default: `250` - Timeout in ms for connection creation
- `max_connections` - Default: `20` - Max number of connections to keep open
- `min_connections` - Default: `2` - Min number of connections to keep open
- `idle_timeout`: Default: `30000` - Time in ms to wait until closing idle connections

## Development
After making any changes, please add or run any required tests. Tests are located in the `test` directory, and can be run via npm:
```
npm test
```

- Source hosted at [GitHub](https://github.com/Clever/thrift-pool)
- Report issues, questions, feature requests on [GitHub Issues](https://github.com/Clever/thrift-pool/issues)

Pull requests are welcome! Please ensure your patches are well tested. Please create separate branches for separate features/patches.
