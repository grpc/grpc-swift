/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Logging
import NIOCore

/// Keys for `Logger` metadata.
enum MetadataKey {
  static let requestID = "grpc_request_id"
  static let connectionID = "grpc_connection_id"

  static let eventLoop = "event_loop"

  static let h2StreamID = "h2_stream_id"
  static let h2ActiveStreams = "h2_active_streams"
  static let h2EndStream = "h2_end_stream"
  static let h2Payload = "h2_payload"
  static let h2Headers = "h2_headers"
  static let h2DataBytes = "h2_data_bytes"
  static let h2GoAwayError = "h2_goaway_error"
  static let h2GoAwayLastStreamID = "h2_goaway_last_stream_id"

  static let error = "error"
}

extension Logger {
  internal mutating func addIPAddressMetadata(local: SocketAddress?, remote: SocketAddress?) {
    if let local = local?.ipAddress {
      self[metadataKey: "grpc.conn.addr_local"] = "\(local)"
    }
    if let remote = remote?.ipAddress {
      self[metadataKey: "grpc.conn.addr_remote"] = "\(remote)"
    }
  }
}
