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
import Foundation
import Logging

extension Logger {
  /// Create a logger and attach the given metadata.
  init(label: String, metadata: Metadata) {
    self.init(label: label)
    for (key, value) in metadata {
      self[metadataKey: key] = value
    }
  }

  /// Create a logger for the given subsystem and attach the given metadata.
  init(subsystem: Subsystem, metadata: Metadata = [:]) {
    self.init(label: "io.grpc.\(subsystem.rawValue)", metadata: metadata)
  }

  /// Create a logger with a label in the format: `"io.grpc.\(suffix)"`.
  init(labelSuffix suffix: String, metadata: Metadata = [:]) {
    self.init(label: "io.grpc.\(suffix)", metadata: metadata)
  }

  /// Creates a copy of the logger and sets metadata with the given key and value on the copy.
  func addingMetadata(key: String, value: MetadataValue) -> Logger {
    var newLogger = self
    newLogger[metadataKey: key] = value
    return newLogger
  }

  /// Labels for logging subsystems.
  enum Subsystem: String {
    case connectivityState = "connectivity_state"
    case clientChannel = "client_channel"
    case clientChannelCall = "client_channel_call"
    case serverChannelCall = "server_channel_call"
    case serverAccess = "server_access"
    case messageReader = "message_reader"
    case nio = "nio"
  }
}

/// Keys for `Logger` metadata.
enum MetadataKey {
  static let requestID = "request_id"
  static let responseType = "response_type"
  static let channelHandler = "channel_handler"
  static let connectionID = "connection_id"
  static let error = "error"
}
