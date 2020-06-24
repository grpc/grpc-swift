//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: helloworld.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import Foundation
import GRPC
import NIO
import NIOHTTP1
import SwiftProtobuf


/// Usage: instantiate Helloworld_GreeterClient, then call methods of this protocol to make API calls.
public protocol Helloworld_GreeterClientProtocol {
  func sayHello(_ request: Helloworld_HelloRequest, callOptions: CallOptions?) -> UnaryCall<Helloworld_HelloRequest, Helloworld_HelloReply>
}

public final class Helloworld_GreeterClient: GRPCClient, Helloworld_GreeterClientProtocol {
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions

  /// Creates a client for the helloworld.Greeter service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }

  /// Sends a greeting.
  ///
  /// - Parameters:
  ///   - request: Request to send to SayHello.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func sayHello(
    _ request: Helloworld_HelloRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Helloworld_HelloRequest, Helloworld_HelloReply> {
    return self.makeUnaryCall(
      path: "/helloworld.Greeter/SayHello",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions
    )
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Helloworld_GreeterProvider: CallHandlerProvider {
  /// Sends a greeting.
  func sayHello(request: Helloworld_HelloRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Helloworld_HelloReply>
}

extension Helloworld_GreeterProvider {
  public var serviceName: String { return "helloworld.Greeter" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "SayHello":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.sayHello(request: request, context: context)
        }
      }

    default: return nil
    }
  }
}


// Provides conformance to `GRPCPayload`
extension Helloworld_HelloRequest: GRPCProtobufPayload {}
extension Helloworld_HelloReply: GRPCProtobufPayload {}
