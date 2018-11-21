//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: echo.proto
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
import SwiftGRPC
import SwiftProtobuf

internal protocol Echo_EchoGetCall: ClientCallUnary {}

fileprivate final class Echo_EchoGetCallBase: ClientCallUnaryBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoGetCall {
  override class var method: String { return "/echo.Echo/Get" }
}

internal protocol Echo_EchoExpandCall: ClientCallServerStreaming {
  /// Do not call this directly, call `receive()` in the protocol extension below instead.
  func _receive(timeout: DispatchTime) throws -> Echo_EchoResponse?
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping (ResultOrRPCError<Echo_EchoResponse?>) -> Void) throws
}

internal extension Echo_EchoExpandCall {
  /// Call this to wait for a result. Blocking.
  func receive(timeout: DispatchTime = .distantFuture) throws -> Echo_EchoResponse? { return try self._receive(timeout: timeout) }
}

fileprivate final class Echo_EchoExpandCallBase: ClientCallServerStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoExpandCall {
  override class var method: String { return "/echo.Echo/Expand" }
}

class Echo_EchoExpandCallTestStub: ClientCallServerStreamingTestStub<Echo_EchoResponse>, Echo_EchoExpandCall {
  override class var method: String { return "/echo.Echo/Expand" }
}

internal protocol Echo_EchoCollectCall: ClientCallClientStreaming {
  /// Send a message to the stream. Nonblocking.
  func send(_ message: Echo_EchoRequest, completion: @escaping (Error?) -> Void) throws
  /// Do not call this directly, call `send()` in the protocol extension below instead.
  func _send(_ message: Echo_EchoRequest, timeout: DispatchTime) throws

  /// Call this to close the connection and wait for a response. Blocking.
  func closeAndReceive() throws -> Echo_EchoResponse
  /// Call this to close the connection and wait for a response. Nonblocking.
  func closeAndReceive(completion: @escaping (ResultOrRPCError<Echo_EchoResponse>) -> Void) throws
}

internal extension Echo_EchoCollectCall {
  /// Send a message to the stream and wait for the send operation to finish. Blocking.
  func send(_ message: Echo_EchoRequest, timeout: DispatchTime = .distantFuture) throws { try self._send(message, timeout: timeout) }
}

fileprivate final class Echo_EchoCollectCallBase: ClientCallClientStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoCollectCall {
  override class var method: String { return "/echo.Echo/Collect" }
}

/// Simple fake implementation of Echo_EchoCollectCall
/// stores sent values for later verification and finall returns a previously-defined result.
class Echo_EchoCollectCallTestStub: ClientCallClientStreamingTestStub<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoCollectCall {
  override class var method: String { return "/echo.Echo/Collect" }
}

internal protocol Echo_EchoUpdateCall: ClientCallBidirectionalStreaming {
  /// Do not call this directly, call `receive()` in the protocol extension below instead.
  func _receive(timeout: DispatchTime) throws -> Echo_EchoResponse?
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping (ResultOrRPCError<Echo_EchoResponse?>) -> Void) throws

  /// Send a message to the stream. Nonblocking.
  func send(_ message: Echo_EchoRequest, completion: @escaping (Error?) -> Void) throws
  /// Do not call this directly, call `send()` in the protocol extension below instead.
  func _send(_ message: Echo_EchoRequest, timeout: DispatchTime) throws

  /// Call this to close the sending connection. Blocking.
  func closeSend() throws
  /// Call this to close the sending connection. Nonblocking.
  func closeSend(completion: (() -> Void)?) throws
}

internal extension Echo_EchoUpdateCall {
  /// Call this to wait for a result. Blocking.
  func receive(timeout: DispatchTime = .distantFuture) throws -> Echo_EchoResponse? { return try self._receive(timeout: timeout) }
}

internal extension Echo_EchoUpdateCall {
  /// Send a message to the stream and wait for the send operation to finish. Blocking.
  func send(_ message: Echo_EchoRequest, timeout: DispatchTime = .distantFuture) throws { try self._send(message, timeout: timeout) }
}

fileprivate final class Echo_EchoUpdateCallBase: ClientCallBidirectionalStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoUpdateCall {
  override class var method: String { return "/echo.Echo/Update" }
}

class Echo_EchoUpdateCallTestStub: ClientCallBidirectionalStreamingTestStub<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoUpdateCall {
  override class var method: String { return "/echo.Echo/Update" }
}


/// Instantiate Echo_EchoServiceClient, then call methods of this protocol to make API calls.
internal protocol Echo_EchoService: ServiceClient {
  /// Synchronous. Unary.
  func get(_ request: Echo_EchoRequest) throws -> Echo_EchoResponse
  /// Asynchronous. Unary.
  func get(_ request: Echo_EchoRequest, completion: @escaping (Echo_EchoResponse?, CallResult) -> Void) throws -> Echo_EchoGetCall

  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  func expand(_ request: Echo_EchoRequest, completion: ((CallResult) -> Void)?) throws -> Echo_EchoExpandCall

  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  func collect(completion: ((CallResult) -> Void)?) throws -> Echo_EchoCollectCall

  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  func update(completion: ((CallResult) -> Void)?) throws -> Echo_EchoUpdateCall

}

internal final class Echo_EchoServiceClient: ServiceClientBase, Echo_EchoService {
  /// Synchronous. Unary.
  internal func get(_ request: Echo_EchoRequest) throws -> Echo_EchoResponse {
    return try Echo_EchoGetCallBase(channel)
      .run(request: request, metadata: metadata)
  }
  /// Asynchronous. Unary.
  internal func get(_ request: Echo_EchoRequest, completion: @escaping (Echo_EchoResponse?, CallResult) -> Void) throws -> Echo_EchoGetCall {
    return try Echo_EchoGetCallBase(channel)
      .start(request: request, metadata: metadata, completion: completion)
  }

  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  internal func expand(_ request: Echo_EchoRequest, completion: ((CallResult) -> Void)?) throws -> Echo_EchoExpandCall {
    return try Echo_EchoExpandCallBase(channel)
      .start(request: request, metadata: metadata, completion: completion)
  }

  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  internal func collect(completion: ((CallResult) -> Void)?) throws -> Echo_EchoCollectCall {
    return try Echo_EchoCollectCallBase(channel)
      .start(metadata: metadata, completion: completion)
  }

  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  internal func update(completion: ((CallResult) -> Void)?) throws -> Echo_EchoUpdateCall {
    return try Echo_EchoUpdateCallBase(channel)
      .start(metadata: metadata, completion: completion)
  }

}

class Echo_EchoServiceTestStub: ServiceClientTestStubBase, Echo_EchoService {
  var getRequests: [Echo_EchoRequest] = []
  var getResponses: [Echo_EchoResponse] = []
  func get(_ request: Echo_EchoRequest) throws -> Echo_EchoResponse {
    getRequests.append(request)
    defer { getResponses.removeFirst() }
    return getResponses.first!
  }
  func get(_ request: Echo_EchoRequest, completion: @escaping (Echo_EchoResponse?, CallResult) -> Void) throws -> Echo_EchoGetCall {
    fatalError("not implemented")
  }

  var expandRequests: [Echo_EchoRequest] = []
  var expandCalls: [Echo_EchoExpandCall] = []
  func expand(_ request: Echo_EchoRequest, completion: ((CallResult) -> Void)?) throws -> Echo_EchoExpandCall {
    expandRequests.append(request)
    defer { expandCalls.removeFirst() }
    return expandCalls.first!
  }

  var collectCalls: [Echo_EchoCollectCall] = []
  func collect(completion: ((CallResult) -> Void)?) throws -> Echo_EchoCollectCall {
    defer { collectCalls.removeFirst() }
    return collectCalls.first!
  }

  var updateCalls: [Echo_EchoUpdateCall] = []
  func update(completion: ((CallResult) -> Void)?) throws -> Echo_EchoUpdateCall {
    defer { updateCalls.removeFirst() }
    return updateCalls.first!
  }

}

/// To build a server, implement a class that conforms to this protocol.
/// If one of the methods returning `ServerStatus?` returns nil,
/// it is expected that you have already returned a status to the client by means of `session.close`.
internal protocol Echo_EchoProvider: ServiceProvider {
  func get(request: Echo_EchoRequest, session: Echo_EchoGetSession) throws -> Echo_EchoResponse
  func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws -> ServerStatus?
  func collect(session: Echo_EchoCollectSession) throws -> Echo_EchoResponse?
  func update(session: Echo_EchoUpdateSession) throws -> ServerStatus?
}

extension Echo_EchoProvider {
  internal var serviceName: String { return "echo.Echo" }

  /// Determines and calls the appropriate request handler, depending on the request's method.
  /// Throws `HandleMethodError.unknownMethod` for methods not handled by this service.
  internal func handleMethod(_ method: String, handler: Handler) throws -> ServerStatus? {
    switch method {
    case "/echo.Echo/Get":
      return try Echo_EchoGetSessionBase(
        handler: handler,
        providerBlock: { try self.get(request: $0, session: $1 as! Echo_EchoGetSessionBase) })
          .run()
    case "/echo.Echo/Expand":
      return try Echo_EchoExpandSessionBase(
        handler: handler,
        providerBlock: { try self.expand(request: $0, session: $1 as! Echo_EchoExpandSessionBase) })
          .run()
    case "/echo.Echo/Collect":
      return try Echo_EchoCollectSessionBase(
        handler: handler,
        providerBlock: { try self.collect(session: $0 as! Echo_EchoCollectSessionBase) })
          .run()
    case "/echo.Echo/Update":
      return try Echo_EchoUpdateSessionBase(
        handler: handler,
        providerBlock: { try self.update(session: $0 as! Echo_EchoUpdateSessionBase) })
          .run()
    default:
      throw HandleMethodError.unknownMethod
    }
  }
}

internal protocol Echo_EchoGetSession: ServerSessionUnary {}

fileprivate final class Echo_EchoGetSessionBase: ServerSessionUnaryBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoGetSession {}

class Echo_EchoGetSessionTestStub: ServerSessionUnaryTestStub, Echo_EchoGetSession {}

internal protocol Echo_EchoExpandSession: ServerSessionServerStreaming {
  /// Send a message to the stream. Nonblocking.
  func send(_ message: Echo_EchoResponse, completion: @escaping (Error?) -> Void) throws
  /// Do not call this directly, call `send()` in the protocol extension below instead.
  func _send(_ message: Echo_EchoResponse, timeout: DispatchTime) throws

  /// Close the connection and send the status. Non-blocking.
  /// This method should be called if and only if your request handler returns a nil value instead of a server status;
  /// otherwise SwiftGRPC will take care of sending the status for you.
  func close(withStatus status: ServerStatus, completion: (() -> Void)?) throws
}

internal extension Echo_EchoExpandSession {
  /// Send a message to the stream and wait for the send operation to finish. Blocking.
  func send(_ message: Echo_EchoResponse, timeout: DispatchTime = .distantFuture) throws { try self._send(message, timeout: timeout) }
}

fileprivate final class Echo_EchoExpandSessionBase: ServerSessionServerStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoExpandSession {}

class Echo_EchoExpandSessionTestStub: ServerSessionServerStreamingTestStub<Echo_EchoResponse>, Echo_EchoExpandSession {}

internal protocol Echo_EchoCollectSession: ServerSessionClientStreaming {
  /// Do not call this directly, call `receive()` in the protocol extension below instead.
  func _receive(timeout: DispatchTime) throws -> Echo_EchoRequest?
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping (ResultOrRPCError<Echo_EchoRequest?>) -> Void) throws

  /// Exactly one of these two methods should be called if and only if your request handler returns nil;
  /// otherwise SwiftGRPC will take care of sending the response and status for you.
  /// Close the connection and send a single result. Non-blocking.
  func sendAndClose(response: Echo_EchoResponse, status: ServerStatus, completion: (() -> Void)?) throws
  /// Close the connection and send an error. Non-blocking.
  /// Use this method if you encountered an error that makes it impossible to send a response.
  /// Accordingly, it does not make sense to call this method with a status of `.ok`.
  func sendErrorAndClose(status: ServerStatus, completion: (() -> Void)?) throws
}

internal extension Echo_EchoCollectSession {
  /// Call this to wait for a result. Blocking.
  func receive(timeout: DispatchTime = .distantFuture) throws -> Echo_EchoRequest? { return try self._receive(timeout: timeout) }
}

fileprivate final class Echo_EchoCollectSessionBase: ServerSessionClientStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoCollectSession {}

class Echo_EchoCollectSessionTestStub: ServerSessionClientStreamingTestStub<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoCollectSession {}

internal protocol Echo_EchoUpdateSession: ServerSessionBidirectionalStreaming {
  /// Do not call this directly, call `receive()` in the protocol extension below instead.
  func _receive(timeout: DispatchTime) throws -> Echo_EchoRequest?
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping (ResultOrRPCError<Echo_EchoRequest?>) -> Void) throws

  /// Send a message to the stream. Nonblocking.
  func send(_ message: Echo_EchoResponse, completion: @escaping (Error?) -> Void) throws
  /// Do not call this directly, call `send()` in the protocol extension below instead.
  func _send(_ message: Echo_EchoResponse, timeout: DispatchTime) throws

  /// Close the connection and send the status. Non-blocking.
  /// This method should be called if and only if your request handler returns a nil value instead of a server status;
  /// otherwise SwiftGRPC will take care of sending the status for you.
  func close(withStatus status: ServerStatus, completion: (() -> Void)?) throws
}

internal extension Echo_EchoUpdateSession {
  /// Call this to wait for a result. Blocking.
  func receive(timeout: DispatchTime = .distantFuture) throws -> Echo_EchoRequest? { return try self._receive(timeout: timeout) }
}

internal extension Echo_EchoUpdateSession {
  /// Send a message to the stream and wait for the send operation to finish. Blocking.
  func send(_ message: Echo_EchoResponse, timeout: DispatchTime = .distantFuture) throws { try self._send(message, timeout: timeout) }
}

fileprivate final class Echo_EchoUpdateSessionBase: ServerSessionBidirectionalStreamingBase<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoUpdateSession {}

class Echo_EchoUpdateSessionTestStub: ServerSessionBidirectionalStreamingTestStub<Echo_EchoRequest, Echo_EchoResponse>, Echo_EchoUpdateSession {}

