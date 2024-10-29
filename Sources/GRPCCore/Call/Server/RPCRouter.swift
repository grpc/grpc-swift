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

/// Stores and provides handlers for RPCs.
///
/// The router stores a handler for each RPC it knows about. Each handler encapsulate the business
/// logic for the RPC which is typically implemented by service owners. To register a handler you
/// can call ``registerHandler(forMethod:deserializer:serializer:handler:)``. You can check whether
/// the router has a handler for a method with ``hasHandler(forMethod:)`` or get a list of all
/// methods with handlers registered by calling ``methods``. You can also remove the handler for a
/// given method by calling ``removeHandler(forMethod:)``.
///
/// In most cases you won't need to interact with the router directly. Instead you should register
/// your services with ``GRPCServer/init(transport:services:interceptors:)`` which will in turn
/// register each method with the router.
///
/// You may wish to not serve all methods from your service in which case you can either:
///
/// 1. Remove individual methods by calling ``removeHandler(forMethod:)``, or
/// 2. Implement ``RegistrableRPCService/registerMethods(with:)`` to register only the methods you
///    want to be served.
public struct RPCRouter: Sendable {
  @usableFromInline
  struct RPCHandler: Sendable {
    @usableFromInline
    let _fn:
      @Sendable (
        _ stream: RPCStream<
          RPCAsyncSequence<RPCRequestPart, any Error>,
          RPCWriter<RPCResponsePart>.Closable
        >,
        _ context: ServerContext,
        _ interceptors: [any ServerInterceptor]
      ) async -> Void

    @inlinable
    init<Input, Output>(
      method: MethodDescriptor,
      deserializer: some MessageDeserializer<Input>,
      serializer: some MessageSerializer<Output>,
      handler: @Sendable @escaping (
        _ request: StreamingServerRequest<Input>,
        _ context: ServerContext
      ) async throws -> StreamingServerResponse<Output>
    ) {
      self._fn = { stream, context, interceptors in
        await ServerRPCExecutor.execute(
          context: context,
          stream: stream,
          deserializer: deserializer,
          serializer: serializer,
          interceptors: interceptors,
          handler: handler
        )
      }
    }

    @inlinable
    func handle(
      stream: RPCStream<
        RPCAsyncSequence<RPCRequestPart, any Error>,
        RPCWriter<RPCResponsePart>.Closable
      >,
      context: ServerContext,
      interceptors: [any ServerInterceptor]
    ) async {
      await self._fn(stream, context, interceptors)
    }
  }

  @usableFromInline
  private(set) var handlers:
    [MethodDescriptor: (handler: RPCHandler, interceptors: [any ServerInterceptor])]

  /// Creates a new router with no methods registered.
  public init() {
    self.handlers = [:]
  }

  /// Returns all descriptors known to the router in an undefined order.
  public var methods: [MethodDescriptor] {
    Array(self.handlers.keys)
  }

  /// Returns the number of methods registered with the router.
  public var count: Int {
    self.handlers.count
  }

  /// Returns whether a handler exists for a given method.
  ///
  /// - Parameter descriptor: A descriptor of the method.
  /// - Returns: Whether a handler exists for the method.
  public func hasHandler(forMethod descriptor: MethodDescriptor) -> Bool {
    return self.handlers.keys.contains(descriptor)
  }

  /// Registers a handler with the router.
  ///
  /// - Note: if a handler already exists for a given method then it will be replaced.
  ///
  /// - Parameters:
  ///   - descriptor: A descriptor for the method to register a handler for.
  ///   - deserializer: A deserializer to deserialize input messages received from the client.
  ///   - serializer: A serializer to serialize output messages to send to the client.
  ///   - handler: The function which handles the request and returns a response.
  @inlinable
  public mutating func registerHandler<Input: Sendable, Output: Sendable>(
    forMethod descriptor: MethodDescriptor,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    handler: @Sendable @escaping (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) {
    let handler = RPCHandler(
      method: descriptor,
      deserializer: deserializer,
      serializer: serializer,
      handler: handler
    )
    self.handlers[descriptor] = (handler, [])
  }

  @inlinable
  public mutating func registerInterceptors(
    pipeline: [ServerInterceptorOperation]
  ) {
    for descriptor in self.handlers.keys {
      let applicableOperations = pipeline.filter { $0.applies(to: descriptor) }
      if !applicableOperations.isEmpty {
        self.handlers[descriptor]?.interceptors = applicableOperations.map { $0.interceptor }
      }
    }
  }

  /// Removes any handler registered for the specified method.
  ///
  /// - Parameter descriptor: A descriptor of the method to remove a handler for.
  /// - Returns: Whether a handler was removed.
  @discardableResult
  public mutating func removeHandler(forMethod descriptor: MethodDescriptor) -> Bool {
    return self.handlers.removeValue(forKey: descriptor) != nil
  }
}

extension RPCRouter {
  internal func handle(
    stream: RPCStream<
      RPCAsyncSequence<RPCRequestPart, any Error>,
      RPCWriter<RPCResponsePart>.Closable
    >,
    context: ServerContext
  ) async {
    if let (handler, interceptors) = self.handlers[stream.descriptor] {
      await handler.handle(stream: stream, context: context, interceptors: interceptors)
    } else {
      // If this throws then the stream must be closed which we can't do anything about, so ignore
      // any error.
      try? await stream.outbound.write(.status(.rpcNotImplemented, [:]))
      await stream.outbound.finish()
    }
  }
}

extension Status {
  fileprivate static let rpcNotImplemented = Status(
    code: .unimplemented,
    message: "Requested RPC isn't implemented by this server."
  )
}
