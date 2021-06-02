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
import Logging
import NIO

/// Wraps `Logger` to always provide the source as "GRPC".
///
/// See https://github.com/apple/swift-log/issues/145 for rationale.
@usableFromInline
internal struct GRPCLogger {
  private var logger: Logger

  internal var unwrapped: Logger {
    return self.logger
  }

  internal init(wrapping logger: Logger) {
    self.logger = logger
  }

  internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get {
      return self.logger[metadataKey: metadataKey]
    }
    set {
      self.logger[metadataKey: metadataKey] = newValue
    }
  }

  internal func trace(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    self.logger.trace(
      message(),
      metadata: metadata(),
      source: "GRPC",
      file: file,
      function: function,
      line: line
    )
  }

  internal func debug(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    self.logger.debug(
      message(),
      metadata: metadata(),
      source: "GRPC",
      file: file,
      function: function,
      line: line
    )
  }

  internal func notice(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    self.logger.notice(
      message(),
      metadata: metadata(),
      source: "GRPC",
      file: file,
      function: function,
      line: line
    )
  }

  internal func warning(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    self.logger.warning(
      message(),
      metadata: metadata(),
      source: "GRPC",
      file: file,
      function: function,
      line: line
    )
  }
}

extension GRPCLogger {
  internal mutating func addIPAddressMetadata(local: SocketAddress?, remote: SocketAddress?) {
    self.logger.addIPAddressMetadata(local: local, remote: remote)
  }
}

extension Logger {
  internal var wrapped: GRPCLogger {
    return GRPCLogger(wrapping: self)
  }
}
