/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

internal import GRPCCore

import struct Foundation.Data

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ControlService: ControlStreamingServiceProtocol {
  func unary(
    request: ServerRequest.Stream<Control.Method.Unary.Input>
  ) async throws -> ServerResponse.Stream<Control.Method.Unary.Output> {
    try await self.handle(request: request)
  }

  func serverStream(
    request: ServerRequest.Stream<Control.Method.ServerStream.Input>
  ) async throws -> ServerResponse.Stream<Control.Method.ServerStream.Output> {
    try await self.handle(request: request)
  }

  func clientStream(
    request: ServerRequest.Stream<Control.Method.ClientStream.Input>
  ) async throws -> ServerResponse.Stream<Control.Method.ClientStream.Output> {
    try await self.handle(request: request)
  }

  func bidiStream(
    request: ServerRequest.Stream<Control.Method.BidiStream.Input>
  ) async throws -> ServerResponse.Stream<Control.Method.BidiStream.Output> {
    try await self.handle(request: request)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ControlService {
  private func handle(
    request: ServerRequest.Stream<ControlInput>
  ) async throws -> ServerResponse.Stream<ControlOutput> {
    var iterator = request.messages.makeAsyncIterator()

    guard let message = try await iterator.next() else {
      // Empty input stream, empty output stream.
      return ServerResponse.Stream { _ in [:] }
    }

    // Check if the request is for a trailers-only response.
    if message.hasStatus, message.isTrailersOnly {
      let trailers = message.echoMetadataInTrailers ? request.metadata.echo() : [:]
      let code = Status.Code(rawValue: message.status.code.rawValue).flatMap { RPCError.Code($0) }

      if let code = code {
        throw RPCError(code: code, message: message.status.message, metadata: trailers)
      } else {
        // Invalid code, the request is invalid, so throw an appropriate error.
        throw RPCError(
          code: .invalidArgument,
          message: "Trailers only response must use a non-OK status code"
        )
      }
    }

    // Not a trailers-only response. Should the metadata be echo'd back?
    let metadata = message.echoMetadataInHeaders ? request.metadata.echo() : [:]

    // The iterator needs to be transferred into the response. This is okay: we won't touch the
    // iterator again from the current concurrency domain.
    let transfer = UnsafeTransfer(iterator)

    return ServerResponse.Stream(metadata: metadata) { writer in
      // Finish dealing with the first message.
      switch try await self.processMessage(message, metadata: request.metadata, writer: writer) {
      case .return(let metadata):
        return metadata
      case .continue:
        ()
      }

      var iterator = transfer.wrappedValue
      // Process the rest of the messages.
      while let message = try await iterator.next() {
        switch try await self.processMessage(message, metadata: request.metadata, writer: writer) {
        case .return(let metadata):
          return metadata
        case .continue:
          ()
        }
      }

      // Input stream finished without explicitly setting a status; finish the RPC cleanly.
      return [:]
    }
  }

  private enum NextProcessingStep {
    case `return`(Metadata)
    case `continue`
  }

  private func processMessage(
    _ input: ControlInput,
    metadata: Metadata,
    writer: RPCWriter<ControlOutput>
  ) async throws -> NextProcessingStep {
    // If messages were requested, build a response and send them back.
    if input.numberOfMessages > 0 {
      let output = ControlOutput.with {
        $0.payload = Data(
          repeating: UInt8(truncatingIfNeeded: input.messageParams.content),
          count: Int(input.messageParams.size)
        )
      }

      for _ in 0 ..< input.numberOfMessages {
        try await writer.write(output)
      }
    }

    // Check whether the RPC should be finished (i.e. the input `hasStatus`).
    guard input.hasStatus else {
      if input.echoMetadataInTrailers {
        // There was no status in the input, but echo metadata in trailers was set. This is an
        // implicit 'ok' status.
        let trailers = input.echoMetadataInTrailers ? metadata.echo() : [:]
        return .return(trailers)
      } else {
        // No status, and not echoing back metadata. Continue consuming the input stream.
        return .continue
      }
    }

    // Build the trailers.
    let trailers = input.echoMetadataInTrailers ? metadata.echo() : [:]

    if input.status.code == .ok {
      return .return(trailers)
    }

    // Non-OK status code, throw an error.
    let code = Status.Code(rawValue: input.status.code.rawValue).flatMap { RPCError.Code($0) }

    if let code = code {
      // Valid error code, throw it.
      throw RPCError(code: code, message: input.status.message, metadata: trailers)
    } else {
      // Invalid error code, throw an appropriate error.
      throw RPCError(
        code: .invalidArgument,
        message: "Invalid error code '\(input.status.code)'"
      )
    }
  }
}

extension Metadata {
  fileprivate func echo() -> Self {
    var copy = Metadata()
    copy.reserveCapacity(self.count)

    for (key, value) in self {
      // Header field names mustn't contain ":".
      let key = "echo-" + key.replacingOccurrences(of: ":", with: "")
      switch value {
      case .string(let stringValue):
        copy.addString(stringValue, forKey: key)
      case .binary(let binaryValue):
        copy.addBinary(binaryValue, forKey: key)
      }
    }

    return copy
  }
}

private struct UnsafeTransfer<Wrapped> {
  var wrappedValue: Wrapped

  init(_ wrappedValue: Wrapped) {
    self.wrappedValue = wrappedValue
  }
}

extension UnsafeTransfer: @unchecked Sendable {}
