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

public import GRPCCore

/// A transport which refines `ServerTransport` to provide the socket address of a listening
/// server.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public protocol ListeningServerTransport: ServerTransport {
  /// Returns the listening address of the server transport once it has started.
  var listeningAddress: SocketAddress { get async throws }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCServer {
  /// Returns the listening address of the server transport once it has started.
  ///
  /// This will be `nil` if the transport doesn't conform to ``ListeningServerTransport``.
  public var listeningAddress: SocketAddress? {
    get async throws {
      if let listener = self.transport as? (any ListeningServerTransport) {
        return try await listener.listeningAddress
      } else {
        return nil
      }
    }
  }
}
