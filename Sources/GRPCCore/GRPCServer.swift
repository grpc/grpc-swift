/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

import Atomics

/// A gRPC server.
///
/// The server accepts connections from clients and listens on each connection for new streams
/// which are initiated by the client. Each stream maps to a single RPC. The server routes accepted
/// streams to a service to handle the RPC or rejects them with an appropriate error if no service
/// can handle the RPC.
///
/// A ``GRPCServer`` listens with a specific transport implementation (for example, HTTP/2 or in-process),
/// and routes requests from the transport to the service instance. You can also use "interceptors",
/// to implement cross-cutting logic which apply to all accepted RPCs. Example uses of interceptors
/// include request filtering, authentication, and logging. Once requests have been intercepted
/// they are passed to a handler which in turn returns a response to send back to the client.
///
/// ## Creating and configuring a server
///
/// The following example demonstrates how to create and configure a server.
///
/// ```swift
/// // Create and an in-process transport.
/// let inProcessTransport = InProcessServerTransport()
///
/// // Create the 'Greeter' and 'Echo' services.
/// let greeter = GreeterService()
/// let echo = EchoService()
///
/// // Create an interceptor.
/// let statsRecorder = StatsRecordingServerInterceptors()
///
/// // Finally create the server.
/// let server = GRPCServer(
///   transport: inProcessTransport,
///   services: [greeter, echo],
///   interceptors: [statsRecorder]
/// )
/// ```
///
/// ## Starting and stopping the server
///
/// Once you have configured the server call ``run()`` to start it. Calling ``run()`` starts the server's
/// transport too. A ``RuntimeError`` is thrown if the transport can't be started or encounters some other
/// runtime error.
///
/// ```swift
/// // Start running the server.
/// try await server.run()
/// ```
///
/// The ``run()`` method won't return until the server has finished handling all requests. You can
/// signal to the server that it should stop accepting new requests by calling ``stopListening()``.
/// This allows the server to drain existing requests gracefully. To stop the server more abruptly
/// you can cancel the task running your server. If your application requires additional resources
/// that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct GRPCServer: Sendable {
  typealias Stream = RPCStream<ServerTransport.Inbound, ServerTransport.Outbound>

  /// The ``ServerTransport`` implementation that the server uses to listen for new requests.
  private let transport: any ServerTransport

  /// The services registered which the server is serving.
  private let router: RPCRouter

  /// A collection of ``ServerInterceptor`` implementations which are applied to all accepted
  /// RPCs.
  ///
  /// RPCs are intercepted in the order that interceptors are added. That is, a request received
  /// from the client will first be intercepted by the first added interceptor followed by the
  /// second, and so on.
  private let interceptors: [any ServerInterceptor]

  /// The state of the server.
  private let state: ManagedAtomic<State>

  private enum State: UInt8, AtomicValue {
    /// The server hasn't been started yet. Can transition to `running` or `stopped`.
    case notStarted
    /// The server is running and accepting RPCs. Can transition to `stopping`.
    case running
    /// The server is stopping and no new RPCs will be accepted. Existing RPCs may run to
    /// completion. May transition to `stopped`.
    case stopping
    /// The server has stopped, no RPCs are in flight and no more will be accepted. This state
    /// is terminal.
    case stopped
  }

  /// Creates a new server with no resources.
  ///
  /// - Parameters:
  ///   - transport: The transport the server should listen on.
  ///   - services: Services offered by the server.
  ///   - interceptors: A collection of interceptors providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  public init(
    transport: any ServerTransport,
    services: [any RegistrableRPCService],
    interceptors: [any ServerInterceptor] = []
  ) {
    var router = RPCRouter()
    for service in services {
      service.registerMethods(with: &router)
    }

    self.init(transport: transport, router: router, interceptors: interceptors)
  }

  /// Creates a new server with no resources.
  ///
  /// - Parameters:
  ///   - transport: The transport the server should listen on.
  ///   - router: A ``RPCRouter`` used by the server to route accepted streams to method handlers.
  ///   - interceptors: A collection of interceptors providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  public init(
    transport: any ServerTransport,
    router: RPCRouter,
    interceptors: [any ServerInterceptor] = []
  ) {
    self.state = ManagedAtomic(.notStarted)
    self.transport = transport
    self.router = router
    self.interceptors = interceptors
  }

  /// Starts the server and runs until the registered transport has closed.
  ///
  /// No RPCs are processed until the configured transport is listening. If the transport fails to start
  /// listening, or if it encounters a runtime error, then ``RuntimeError`` is thrown.
  ///
  /// This function returns when the configured transport has stopped listening and all requests have been
  /// handled. You can signal to the transport that it should stop listening by calling
  /// ``stopListening()``. The server will continue to process existing requests.
  ///
  /// To stop the server more abruptly you can cancel the task that this function is running in.
  ///
  /// - Note: You can only call this function once, repeated calls will result in a
  ///   ``RuntimeError`` being thrown.
  public func run() async throws {
    let (wasNotStarted, actualState) = self.state.compareExchange(
      expected: .notStarted,
      desired: .running,
      ordering: .sequentiallyConsistent
    )

    guard wasNotStarted else {
      switch actualState {
      case .notStarted:
        fatalError()
      case .running:
        throw RuntimeError(
          code: .serverIsAlreadyRunning,
          message: "The server is already running and can only be started once."
        )

      case .stopping, .stopped:
        throw RuntimeError(
          code: .serverIsStopped,
          message: "The server has stopped and can only be started once."
        )
      }
    }

    // When we exit this function we must have stopped.
    defer {
      self.state.store(.stopped, ordering: .sequentiallyConsistent)
    }

    do {
      try await transport.listen { stream in
        await self.router.handle(stream: stream, interceptors: self.interceptors)
      }
    } catch {
      throw RuntimeError(
        code: .transportError,
        message: "Server transport threw an error.",
        cause: error
      )
    }
  }

  /// Signal to the server that it should stop listening for new requests.
  ///
  /// By calling this function you indicate to clients that they mustn't start new requests
  /// against this server. Once the server has processed all requests the ``run()`` method returns.
  ///
  /// Calling this on a server which is already stopping or has stopped has no effect.
  public func stopListening() {
    let (wasRunning, actual) = self.state.compareExchange(
      expected: .running,
      desired: .stopping,
      ordering: .sequentiallyConsistent
    )

    if wasRunning {
      self.transport.stopListening()
    } else {
      switch actual {
      case .notStarted:
        let (exchanged, _) = self.state.compareExchange(
          expected: .notStarted,
          desired: .stopped,
          ordering: .sequentiallyConsistent
        )

        // Lost a race with 'run()', try again.
        if !exchanged {
          self.stopListening()
        }

      case .running:
        // Unreachable, this branch only happens when the initial exchange didn't take place.
        fatalError()

      case .stopping, .stopped:
        // Already stopping/stopped, ignore.
        ()
      }
    }
  }
}
