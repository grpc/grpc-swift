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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
internal struct ClientStreamExecutor<Transport: ClientTransport> {
  /// The client transport to execute the stream on.
  @usableFromInline
  let _transport: Transport

  /// An `AsyncStream` and continuation to send and receive processing events on.
  @usableFromInline
  let _work: (stream: AsyncStream<_Event>, continuation: AsyncStream<_Event>.Continuation)

  @usableFromInline
  let _watermarks: (low: Int, high: Int)

  @usableFromInline
  enum _Event: Sendable {
    /// Send the request on the outbound stream.
    case request(ClientRequest.Stream<[UInt8]>, Transport.Outbound)
    /// Receive the response from the inbound stream.
    case response(
      RPCWriter<ClientResponse.Stream<[UInt8]>.Contents.BodyPart>.Closable,
      UnsafeTransfer<Transport.Inbound.AsyncIterator>
    )
  }

  @inlinable
  init(transport: Transport, responseStreamWatermarks: (low: Int, high: Int) = (16, 32)) {
    self._transport = transport
    self._work = AsyncStream.makeStream()
    self._watermarks = responseStreamWatermarks
  }

  /// Run the stream executor.
  ///
  /// This is required to be running until the response returned from ``execute(request:method:)``
  /// has been processed.
  @inlinable
  func run() async {
    await withTaskGroup(of: Void.self) { group in
      for await event in self._work.stream {
        switch event {
        case .request(let request, let outboundStream):
          group.addTask {
            await self._processRequest(request, on: outboundStream)
          }

        case .response(let writer, let iterator):
          group.addTask {
            await self._processResponse(writer: writer, iterator: iterator)
          }
        }
      }
    }
  }

  /// Execute a request on the stream executor.
  ///
  /// The ``run()`` method must be running at the same time as this method.
  ///
  /// - Parameters:
  ///   - request: A streaming request.
  ///   - method: A description of the method to call.
  /// - Returns: A streamed response.
  @inlinable
  func execute(
    request: ClientRequest.Stream<[UInt8]>,
    method: MethodDescriptor
  ) async -> ClientResponse.Stream<[UInt8]> {
    // Each execution method can add work to process in the 'run' method. They must not add
    // new work once they return.
    defer { self._work.continuation.finish() }

    // Open a stream. Return a failed response if we can't open one.
    let stream: RPCStream<Transport.Inbound, Transport.Outbound>

    do {
      stream = try await self._transport.openStream(descriptor: method)
    } catch let error as RPCError {
      return ClientResponse.Stream(error: error)
    } catch let other {
      let error = RPCError(
        code: .unknown,
        message: "Transport failed to create stream.",
        cause: other
      )
      return ClientResponse.Stream(error: error)
    }

    // Start processing the request.
    self._work.continuation.yield(.request(request, stream.outbound))

    let part = await self._waitForFirstResponsePart(on: stream.inbound)

    // Wait for the first response to determine how to handle the response.
    switch part {
    case .metadata(let metadata, let iterator):
      // Expected happy case: the server is processing the request.

      // TODO: (optimisation) use a hint about whether the response is streamed. Use a specialised
      // sequence to avoid allocations if it isn't
      let responses = RPCAsyncSequence.makeBackpressuredStream(
        of: ClientResponse.Stream<[UInt8]>.Contents.BodyPart.self,
        watermarks: self._watermarks
      )

      self._work.continuation.yield(.response(responses.writer, iterator))
      return ClientResponse.Stream(metadata: metadata, bodyParts: responses.stream)

    case .status(let status, let metadata):
      // Expected unhappy (but okay) case; the server rejected the request.
      return ClientResponse.Stream(status: status, metadata: metadata)

    case .failed(let error):
      // Very unhappy case: the server did something unexpected.
      return ClientResponse.Stream(error: error)
    }
  }

  @inlinable
  func _processRequest<Stream: ClosableRPCWriterProtocol<RPCRequestPart>>(
    _ request: ClientRequest.Stream<[UInt8]>,
    on stream: Stream
  ) async {
    let result = await Result {
      try await stream.write(.metadata(request.metadata))
      try await request.producer(.map(into: stream) { .message($0) })
    }.castError(to: RPCError.self) { other in
      RPCError(code: .unknown, message: "Write failed.", cause: other)
    }

    switch result {
    case .success:
      stream.finish()
    case .failure(let error):
      stream.finish(throwing: error)
    }
  }

  @usableFromInline
  enum OnFirstResponsePart: Sendable {
    case metadata(Metadata, UnsafeTransfer<Transport.Inbound.AsyncIterator>)
    case status(Status, Metadata)
    case failed(RPCError)
  }

  @inlinable
  func _waitForFirstResponsePart(
    on stream: Transport.Inbound
  ) async -> OnFirstResponsePart {
    var iterator = stream.makeAsyncIterator()
    let result = await Result<OnFirstResponsePart, Error> {
      switch try await iterator.next() {
      case .metadata(let metadata):
        return .metadata(metadata, UnsafeTransfer(iterator))

      case .status(let status, let metadata):
        return .status(status, metadata)

      case .message:
        let error = RPCError(
          code: .internalError,
          message: """
            Invalid stream. The transport returned a message as the first element in the \
            stream, expected metadata. This is likely to be a transport-specific bug.
            """
        )
        return .failed(error)

      case .none:
        let error = RPCError(
          code: .internalError,
          message: """
            Invalid stream. The transport returned an empty stream. This is likely to be \
            a transport-specific bug.
            """
        )
        return .failed(error)
      }
    }.castError(to: RPCError.self) { error in
      RPCError(
        code: .unknown,
        message: "The transport threw an unexpected error.",
        cause: error
      )
    }

    switch result {
    case .success(let firstPart):
      return firstPart
    case .failure(let error):
      return .failed(error)
    }
  }

  @inlinable
  func _processResponse(
    writer: RPCWriter<ClientResponse.Stream<[UInt8]>.Contents.BodyPart>.Closable,
    iterator: UnsafeTransfer<Transport.Inbound.AsyncIterator>
  ) async {
    var iterator = iterator.wrappedValue
    let result = await Result {
      while let next = try await iterator.next() {
        switch next {
        case .metadata(let metadata):
          let error = RPCError(
            code: .internalError,
            message: """
              Received multiple sets of metadata from the transport. This is likely to be a \
              transport specific bug. Metadata received: '\(metadata)'.
              """
          )
          throw error

        case .message(let bytes):
          try await writer.write(.message(bytes))

        case .status(let status, let metadata):
          if let error = RPCError(status: status, metadata: metadata) {
            throw error
          } else {
            try await writer.write(.trailingMetadata(metadata))
          }
        }
      }
    }.castError(to: RPCError.self) { error in
      RPCError(
        code: .unknown,
        message: "Can't write to output stream, cancelling RPC.",
        cause: error
      )
    }

    // Make sure the writer is finished.
    switch result {
    case .success:
      writer.finish()
    case .failure(let error):
      writer.finish(throwing: error)
    }
  }
}
