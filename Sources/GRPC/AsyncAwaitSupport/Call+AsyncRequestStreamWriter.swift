/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.6)
import NIOCore

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Call where Request: Sendable, Response: Sendable {
  typealias AsyncWriter = NIOAsyncWriter<
    (Request, Compression),
    GRPCAsyncWriterSinkDelegate<(Request, Compression)>
  >
  internal func makeRequestStreamWriter()
    -> (GRPCAsyncRequestStreamWriter<Request>, AsyncWriter.Sink) {
    let delegate = GRPCAsyncWriterSinkDelegate<(Request, Compression)>(
      didYield: { requests in
        for (request, compression) in requests {
          let compress = compression
            .isEnabled(callDefault: self.options.messageEncoding.enabledForRequests)

          // TODO: be smarter about inserting flushes.
          // We currently always flush after every write which may trigger more syscalls than necessary.
          let metadata = MessageMetadata(compress: compress, flush: true)
          self.send(.message(request, metadata), promise: nil)
        }
      },
      didTerminate: { _ in self.send(.end, promise: nil) }
    )

    let writer = NIOAsyncWriter.makeWriter(isWritable: false, delegate: delegate)

    // Start as not-writable; writability will be toggled when the stream comes up.
    return (GRPCAsyncRequestStreamWriter<Request>(asyncWriter: writer.writer), writer.sink)
  }
}

#endif // compiler(>=5.6)
