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
import NIOHPACK

public enum ClientRequestPart<Request> {
  /// User provided metadata sent at the start of the request stream.
  case metadata(HPACKHeaders)

  /// A message to send to the server.
  case message(Request, Metadata)

  /// End the request stream.
  case end

  /// Metadata associated with a request message.
  public struct Metadata: Equatable {
    /// Whether the message should be compressed. If compression has not been enabled on the RPC
    /// then setting is ignored.
    public var compress: Bool

    /// Whether the underlying transported should be 'flushed' after writing this message. If a batch
    /// of messages is to be sent then flushing only after the last message may improve
    /// performance.
    public var flush: Bool

    public init(compress: Bool, flush: Bool) {
      self.compress = compress
      self.flush = flush
    }
  }
}

public enum ClientResponsePart<Response> {
  /// The initial metadata returned by the server.
  case metadata(HPACKHeaders)

  /// A response message from the server.
  case message(Response)

  /// The end of response stream sent by the server.
  case end(GRPCStatus, HPACKHeaders)

  /// Error.
  case error(Error)
}
