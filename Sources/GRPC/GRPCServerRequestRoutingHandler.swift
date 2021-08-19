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
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import SwiftProtobuf

/// Provides `GRPCServerHandlerProtocol` objects for the methods on a particular service name.
///
/// Implemented by the generated code.
public protocol CallHandlerProvider: AnyObject {
  /// The name of the service this object is providing methods for, including the package path.
  ///
  /// - Example: "io.grpc.Echo.EchoService"
  var serviceName: Substring { get }

  /// Returns a call handler for the method with the given name, if this service provider implements
  /// the given method. Returns `nil` if the method is not handled by this provider.
  /// - Parameters:
  ///   - name: The name of the method to handle.
  ///   - context: An opaque context providing components to construct the handler with.
  func handle(method name: Substring, context: CallHandlerContext) -> GRPCServerHandlerProtocol?
}

// This is public because it will be passed into generated code, all members are `internal` because
// the context will get passed from generated code back into gRPC library code and all members should
// be considered an implementation detail to the user.
public struct CallHandlerContext {
  @usableFromInline
  internal var errorDelegate: ServerErrorDelegate?
  @usableFromInline
  internal var logger: Logger
  @usableFromInline
  internal var encoding: ServerMessageEncoding
  @usableFromInline
  internal var eventLoop: EventLoop
  @usableFromInline
  internal var path: String
  @usableFromInline
  internal var remoteAddress: SocketAddress?
  @usableFromInline
  internal var responseWriter: GRPCServerResponseWriter
  @usableFromInline
  internal var allocator: ByteBufferAllocator
  @usableFromInline
  internal var closeFuture: EventLoopFuture<Void>
}

/// A call URI split into components.
struct CallPath {
  /// The name of the service to call.
  var service: String.UTF8View.SubSequence
  /// The name of the method to call.
  var method: String.UTF8View.SubSequence

  /// Character used to split the path into components.
  private let pathSplitDelimiter = UInt8(ascii: "/")

  /// Split a path into service and method.
  /// Split is done in UTF8 as this turns out to be approximately 10x faster than a simple split.
  /// URI format: "/package.Servicename/MethodName"
  init?(requestURI: String) {
    var utf8View = requestURI.utf8[...]
    // Check and remove the split character at the beginning.
    guard let prefix = utf8View.trimPrefix(to: self.pathSplitDelimiter), prefix.isEmpty else {
      return nil
    }
    guard let service = utf8View.trimPrefix(to: pathSplitDelimiter) else {
      return nil
    }
    guard let method = utf8View.trimPrefix(to: pathSplitDelimiter) else {
      return nil
    }

    self.service = service
    self.method = method
  }
}

extension Collection where Self == Self.SubSequence, Self.Element: Equatable {
  /// Trims out the prefix up to `separator`, and returns it.
  /// Sets self to the subsequence after the separator, and returns the subsequence before the separator.
  /// If self is empty returns `nil`
  /// - parameters:
  ///     - separator : The Element between the head which is returned and the rest which is left in self.
  /// - returns: SubSequence containing everything between the beginning and the first occurrence of
  /// `separator`.  If `separator` is not found this will be the entire Collection. If the collection is empty
  /// returns `nil`
  mutating func trimPrefix(to separator: Element) -> SubSequence? {
    guard !self.isEmpty else {
      return nil
    }
    if let separatorIndex = self.firstIndex(of: separator) {
      let indexAfterSeparator = self.index(after: separatorIndex)
      defer { self = self[indexAfterSeparator...] }
      return self[..<separatorIndex]
    } else {
      defer { self = self[self.endIndex...] }
      return self[...]
    }
  }
}
