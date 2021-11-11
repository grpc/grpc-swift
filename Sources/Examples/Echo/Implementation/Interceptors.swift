/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import EchoModel
import GRPC
import NIOCore

// All client interceptors derive from the 'ClientInterceptor' base class. We know the request and
// response types for all Echo RPCs are the same: so we'll use them concretely here, allowing us
// to access fields on each type as we intercept them.
class LoggingEchoClientInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  /// Called when the interceptor has received a request part to handle.
  ///
  /// - Parameters:
  ///   - part: The request part to send to the server.
  ///   - promise: A promise to complete once the request part has been written to the network.
  ///   - context: An interceptor context which may be used to forward the request part to the next
  ///     interceptor.
  override func send(
    _ part: GRPCClientRequestPart<Echo_EchoRequest>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    // The (user-provided) request headers, we send these at the start of each RPC. They will be
    // augmented with transport specific headers once the request part reaches the transport.
    case let .metadata(headers):
      print("> Starting '\(context.path)' RPC, headers:", prettify(headers))

    // The request message and metadata (ignored here). For unary and server-streaming RPCs we
    // expect exactly one message, for client-streaming and bidirectional streaming RPCs any number
    // of messages is permitted.
    case let .message(request, _):
      print("> Sending request with text '\(request.text)'")

    // The end of the request stream: must be sent exactly once, after which no more messages may
    // be sent.
    case .end:
      print("> Closing request stream")
    }

    // Forward the request part to the next interceptor.
    context.send(part, promise: promise)
  }

  /// Called when the interceptor has received a response part to handle.
  ///
  /// - Parameters:
  ///   - part: The response part received from the server.
  ///   - context: An interceptor context which may be used to forward the response part to the next
  ///     interceptor.
  override func receive(
    _ part: GRPCClientResponsePart<Echo_EchoResponse>,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    // The response headers received from the server. We expect to receive these once at the start
    // of a response stream, however, it is also valid to see no 'metadata' parts on the response
    // stream if the server rejects the RPC (in which case we expect the 'end' part).
    case let .metadata(headers):
      print("< Received headers:", prettify(headers))

    // A response message received from the server. For unary and client-streaming RPCs we expect
    // one message. For server-streaming and bidirectional-streaming we expect any number of
    // messages (including zero).
    case let .message(response):
      print("< Received response with text '\(response.text)'")

    // The end of the response stream (and by extension, request stream). We expect one 'end' part,
    // after which no more response parts may be received and no more request parts will be sent.
    case let .end(status, trailers):
      print("< Response stream closed with status: '\(status)' and trailers:", prettify(trailers))
    }

    // Forward the response part to the next interceptor.
    context.receive(part)
  }
}

/// This class is an implementation of a *generated* protocol for the client which has one factory
/// method per RPC returning the interceptors to use. The relevant factory method is call when
/// invoking each RPC. An implementation of this protocol can be set on the generated client.
public class ExampleClientInterceptorFactory: Echo_EchoClientInterceptorFactoryProtocol {
  public init() {}

  // Returns an array of interceptors to use for the 'Get' RPC.
  public func makeGetInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Expand' RPC.
  public func makeExpandInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Collect' RPC.
  public func makeCollectInterceptors()
    -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Update' RPC.
  public func makeUpdateInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }
}
