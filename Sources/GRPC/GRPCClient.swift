/*
 * Copyright 2019, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP2
import SwiftProtobuf

/// A gRPC client.
public protocol GRPCClient: GRPCSendable {
  /// The gRPC channel over which RPCs are sent and received. Note that this is distinct
  /// from `NIO.Channel`.
  var channel: GRPCChannel { get }

  /// The call options to use should the user not provide per-call options.
  var defaultCallOptions: CallOptions { get set }
}

// MARK: Convenience methods

extension GRPCClient {
  public func makeUnaryCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> UnaryCall<Request, Response> {
    return self.channel.makeUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> UnaryCall<Request, Response> {
    return self.channel.makeUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeServerStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.channel.makeServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors,
      handler: handler
    )
  }

  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.channel.makeServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors,
      handler: handler
    )
  }

  public func makeClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> ClientStreamingCall<Request, Response> {
    return self.channel.makeClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> ClientStreamingCall<Request, Response> {
    return self.channel.makeClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.channel.makeBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors,
      handler: handler
    )
  }

  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.channel.makeBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors,
      handler: handler
    )
  }
}

/// A client which has no generated stubs and may be used to create gRPC calls manually.
/// See `GRPCClient` for details.
///
/// Example:
///
/// ```
/// let client = AnyServiceClient(channel: channel)
/// let rpc: UnaryCall<Request, Response> = client.makeUnaryCall(
///   path: "/serviceName/methodName",
///   request: .with { ... },
/// }
/// ```
@available(*, deprecated, renamed: "GRPCAnyServiceClient")
public final class AnyServiceClient: GRPCClient {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions

  /// The gRPC channel over which RPCs are sent and received.
  public let channel: GRPCChannel

  /// The default options passed to each RPC unless passed for each RPC.
  public var defaultCallOptions: CallOptions {
    get { return self.lock.withLock { self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }

  /// Creates a client which may be used to call any service.
  ///
  /// - Parameters:
  ///   - connection: `ClientConnection` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
  }
}

#if swift(>=5.6)
// Unchecked because mutable state is protected by a lock.
@available(*, deprecated, renamed: "GRPCAnyServiceClient")
extension AnyServiceClient: @unchecked GRPCSendable {}
#endif // swift(>=5.6)

/// A client which has no generated stubs and may be used to create gRPC calls manually.
/// See `GRPCClient` for details.
///
/// Example:
///
/// ```
/// let client = GRPCAnyServiceClient(channel: channel)
/// let rpc: UnaryCall<Request, Response> = client.makeUnaryCall(
///   path: "/serviceName/methodName",
///   request: .with { ... },
/// }
/// ```
public struct GRPCAnyServiceClient: GRPCClient {
  public let channel: GRPCChannel

  /// The default options passed to each RPC unless passed for each RPC.
  public var defaultCallOptions: CallOptions

  /// Creates a client which may be used to call any service.
  ///
  /// - Parameters:
  ///   - connection: `ClientConnection` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }
}
