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

import GRPCCore
import NIOCore

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public enum ServerConnection {
  public enum Stream {
    @_spi(Package)
    public struct Outbound: ClosableRPCWriterProtocol {
      public typealias Element = RPCResponsePart

      private let responseWriter: NIOAsyncChannelOutboundWriter<RPCResponsePart>
      private let http2Stream: NIOAsyncChannel<RPCRequestPart, RPCResponsePart>

      public init(
        responseWriter: NIOAsyncChannelOutboundWriter<RPCResponsePart>,
        http2Stream: NIOAsyncChannel<RPCRequestPart, RPCResponsePart>
      ) {
        self.responseWriter = responseWriter
        self.http2Stream = http2Stream
      }

      public func write(_ element: RPCResponsePart) async throws {
        try await self.responseWriter.write(element)
      }

      public func write(contentsOf elements: some Sequence<Self.Element>) async throws {
        try await self.responseWriter.write(contentsOf: elements)
      }

      public func finish() {
        self.responseWriter.finish()
      }

      public func finish(throwing error: any Error) {
        // Fire the error inbound; this fails the inbound writer.
        self.http2Stream.channel.pipeline.fireErrorCaught(error)
      }
    }
  }
}
