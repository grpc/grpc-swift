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
import Foundation
import SwiftProtobuf

/// A GRPC client.
public protocol GRPCClient {
  /// The connection providing the underlying HTTP/2 channel for this client.
  var connection: ClientConnection { get }

  /// The call options to use should the user not provide per-call options.
  var defaultCallOptions: CallOptions { get set }
}

extension GRPCClient {
  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    responseType: Response.Type = Response.self
  ) -> UnaryCall<Request, Response> {
    return UnaryCall(
      connection: self.connection,
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      errorDelegate: self.connection.configuration.errorDelegate)
  }

  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return ServerStreamingCall(
      connection: self.connection,
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      errorDelegate: self.connection.configuration.errorDelegate,
      handler: handler)
  }

  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions? = nil,
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> ClientStreamingCall<Request, Response> {
    return ClientStreamingCall(
      connection: self.connection,
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      errorDelegate: self.connection.configuration.errorDelegate)
  }

  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions? = nil,
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return BidirectionalStreamingCall(
      connection: self.connection,
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      errorDelegate: self.connection.configuration.errorDelegate,
      handler: handler)
  }
}

/// A client which has no generated stubs and may be used to create gRPC calls manually.
/// See `GRPCClient` for details.
public final class AnyServiceClient: GRPCClient {
  public let connection: ClientConnection
  public var defaultCallOptions: CallOptions

  /// Creates a client which may be used to call any service.
  ///
  /// - Parameters:
  ///   - connection: `ClientConnection` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(connection: ClientConnection, defaultCallOptions: CallOptions = CallOptions()) {
    self.connection = connection
    self.defaultCallOptions = defaultCallOptions
  }
}
