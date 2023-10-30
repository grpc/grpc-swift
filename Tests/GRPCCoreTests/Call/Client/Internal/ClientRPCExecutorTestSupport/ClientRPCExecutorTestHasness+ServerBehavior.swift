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
import XCTest

@testable import GRPCCore

extension ClientRPCExecutorTestHarness {
  struct ServerStreamHandler: Sendable {
    private let handler:
      @Sendable (
        _ stream: RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>
      ) async throws -> Void

    init(
      _ handler: @escaping @Sendable (
        RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>
      ) async throws -> Void
    ) {
      self.handler = handler
    }

    func handle<Inbound: AsyncSequence, Outbound: ClosableRPCWriterProtocol>(
      stream: RPCStream<Inbound, Outbound>
    ) async throws where Inbound.Element == RPCRequestPart, Outbound.Element == RPCResponsePart {
      let erased = RPCStream(
        descriptor: stream.descriptor,
        inbound: RPCAsyncSequence(wrapping: stream.inbound),
        outbound: RPCWriter.Closable(wrapping: stream.outbound)
      )

      try await self.handler(erased)
    }
  }
}

extension ClientRPCExecutorTestHarness.ServerStreamHandler {
  static var echo: Self {
    return Self {
      stream in
      let response = stream.inbound.map { part -> RPCResponsePart in
        switch part {
        case .metadata(let metadata):
          return .metadata(metadata)
        case .message(let bytes):
          return .message(bytes)
        }
      }

      try await stream.outbound.write(contentsOf: response)
      try await stream.outbound.write(.status(Status(code: .ok, message: ""), [:]))
      stream.outbound.finish()
    }
  }

  static func reject(
    withError error: RPCError,
    consumeInbound: Bool = false
  ) -> Self {
    return Self { stream in
      if consumeInbound {
        for try await _ in stream.inbound {}
      }

      // All error codes are valid status codes, '!' is safe.
      let status = Status(code: Status.Code(error.code), message: error.message)
      try await stream.outbound.write(.status(status, error.metadata))
      stream.outbound.finish()
    }
  }

  static var failTest: Self {
    return Self { stream in
      XCTFail("Server accepted unexpected stream")
      let status = Status(code: .unknown, message: "Unexpected stream")
      try await stream.outbound.write(.status(status, [:]))
      stream.outbound.finish()
    }
  }

  static func attemptBased(_ onAttempt: @Sendable @escaping (_ attempt: Int) -> Self) -> Self {
    let attempts = ManagedAtomic(1)
    return Self { stream in
      let attempt = attempts.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
      let handler = onAttempt(attempt)
      try await handler.handle(stream: stream)
    }
  }

  static func sleepFor(duration: Duration, then handler: Self) -> Self {
    return Self { stream in
      try await Task.sleep(until: .now.advanced(by: duration), clock: .continuous)
      try await handler.handle(stream: stream)
    }
  }
}
