/**
 * @fileoverview gRPC-Web generated client stub for echo
 * @enhanceable
 * @public
 */

// GENERATED CODE -- DO NOT EDIT!



const grpc = {};
grpc.web = require('grpc-web');

const proto = {};
proto.echo = require('./echo_pb.js');

/**
 * @param {string} hostname
 * @param {?Object} credentials
 * @param {?Object} options
 * @constructor
 * @struct
 * @final
 */
proto.echo.EchoClient =
    function(hostname, credentials, options) {
  if (!options) options = {};
  options['format'] = 'text';

  /**
   * @private @const {!grpc.web.GrpcWebClientBase} The client
   */
  this.client_ = new grpc.web.GrpcWebClientBase(options);

  /**
   * @private @const {string} The hostname
   */
  this.hostname_ = hostname;

  /**
   * @private @const {?Object} The credentials to be used to connect
   *    to the server
   */
  this.credentials_ = credentials;

  /**
   * @private @const {?Object} Options for the client
   */
  this.options_ = options;
};


/**
 * @param {string} hostname
 * @param {?Object} credentials
 * @param {?Object} options
 * @constructor
 * @struct
 * @final
 */
proto.echo.EchoPromiseClient =
    function(hostname, credentials, options) {
  if (!options) options = {};
  options['format'] = 'text';

  /**
   * @private @const {!proto.echo.EchoClient} The delegate callback based client
   */
  this.delegateClient_ = new proto.echo.EchoClient(
      hostname, credentials, options);

};


/**
 * @const
 * @type {!grpc.web.AbstractClientBase.MethodInfo<
 *   !proto.echo.EchoRequest,
 *   !proto.echo.EchoResponse>}
 */
const methodInfo_Echo_Get = new grpc.web.AbstractClientBase.MethodInfo(
  proto.echo.EchoResponse,
  /** @param {!proto.echo.EchoRequest} request */
  function(request) {
    return request.serializeBinary();
  },
  proto.echo.EchoResponse.deserializeBinary
);


/**
 * @param {!proto.echo.EchoRequest} request The
 *     request proto
 * @param {!Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.Error, ?proto.echo.EchoResponse)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.echo.EchoResponse>|undefined}
 *     The XHR Node Readable Stream
 */
proto.echo.EchoClient.prototype.get =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/echo.Echo/Get',
      request,
      metadata,
      methodInfo_Echo_Get,
      callback);
};


/**
 * @param {!proto.echo.EchoRequest} request The
 *     request proto
 * @param {!Object<string, string>} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.echo.EchoResponse>}
 *     The XHR Node Readable Stream
 */
proto.echo.EchoPromiseClient.prototype.get =
    function(request, metadata) {
  return new Promise((resolve, reject) => {
    this.delegateClient_.get(
      request, metadata, (error, response) => {
        error ? reject(error) : resolve(response);
      });
  });
};


/**
 * @const
 * @type {!grpc.web.AbstractClientBase.MethodInfo<
 *   !proto.echo.EchoRequest,
 *   !proto.echo.EchoResponse>}
 */
const methodInfo_Echo_Expand = new grpc.web.AbstractClientBase.MethodInfo(
  proto.echo.EchoResponse,
  /** @param {!proto.echo.EchoRequest} request */
  function(request) {
    return request.serializeBinary();
  },
  proto.echo.EchoResponse.deserializeBinary
);


/**
 * @param {!proto.echo.EchoRequest} request The request proto
 * @param {!Object<string, string>} metadata User defined
 *     call metadata
 * @return {!grpc.web.ClientReadableStream<!proto.echo.EchoResponse>}
 *     The XHR Node Readable Stream
 */
proto.echo.EchoClient.prototype.expand =
    function(request, metadata) {
  return this.client_.serverStreaming(this.hostname_ +
      '/echo.Echo/Expand',
      request,
      metadata,
      methodInfo_Echo_Expand);
};


/**
 * @param {!proto.echo.EchoRequest} request The request proto
 * @param {!Object<string, string>} metadata User defined
 *     call metadata
 * @return {!grpc.web.ClientReadableStream<!proto.echo.EchoResponse>}
 *     The XHR Node Readable Stream
 */
proto.echo.EchoPromiseClient.prototype.expand =
    function(request, metadata) {
  return this.delegateClient_.client_.serverStreaming(this.delegateClient_.hostname_ +
      '/echo.Echo/Expand',
      request,
      metadata,
      methodInfo_Echo_Expand);
};


module.exports = proto.echo;
