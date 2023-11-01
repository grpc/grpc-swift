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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ClientResponse.Single {
  /// Converts a streaming response into a single response.
  ///
  /// - Parameter response: The streaming response to convert.
  init(stream response: ClientResponse.Stream<Message>) async {
    switch response.accepted {
    case .success(let contents):
      do {
        let metadata = contents.metadata
        var iterator = contents.bodyParts.makeAsyncIterator()

        // Happy path: message, trailing metadata, nil.
        let part1 = try await iterator.next()
        let part2 = try await iterator.next()
        let part3 = try await iterator.next()

        switch (part1, part2, part3) {
        case (.some(.message(let message)), .some(.trailingMetadata(let trailingMetadata)), .none):
          let contents = Contents(
            metadata: metadata,
            message: message,
            trailingMetadata: trailingMetadata
          )
          self.accepted = .success(contents)

        case (.some(.message), .some(.message), _):
          let error = RPCError(
            code: .unimplemented,
            message: """
              Multiple messages received, but only one is expected. The server may have \
              incorrectly implemented the RPC or the client and server may have a different \
              opinion on whether this RPC streams responses.
              """
          )
          self.accepted = .failure(error)

        case (.some(.trailingMetadata), .none, .none):
          let error = RPCError(
            code: .unimplemented,
            message: "No messages received, exactly one was expected."
          )
          self.accepted = .failure(error)

        case (_, _, _):
          let error = RPCError(
            code: .internalError,
            message: """
              The stream from the client transport is invalid. This is likely to be an incorrectly \
              implemented transport. Received parts: \([part1, part2, part3])."
              """
          )
          self.accepted = .failure(error)
        }
      } catch let error as RPCError {
        // Known error type.
        self.accepted = .failure(error)
      } catch {
        // Unexpected, but should be handled nonetheless.
        self.accepted = .failure(RPCError(code: .unknown, message: String(describing: error)))
      }

    case .failure(let error):
      self.accepted = .failure(error)
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ClientResponse.Stream {
  /// Creates a streaming response from the given status and metadata.
  ///
  /// If the ``Status`` has code ``Status/Code-swift.struct/ok`` then an accepted stream is created
  /// containing only the provided metadata. Otherwise a failed response is returned with an error
  /// created from the status and metadata.
  ///
  /// - Parameters:
  ///   - status: The status received from the server.
  ///   - metadata: The metadata received from the server.
  @inlinable
  init(status: Status, metadata: Metadata) {
    if let error = RPCError(status: status, metadata: metadata) {
      self.accepted = .failure(error)
    } else {
      self.accepted = .success(.init(metadata: [:], bodyParts: .one(.trailingMetadata(metadata))))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ClientResponse.Stream {
  /// Returns a new response which maps the messages of this response.
  ///
  /// - Parameter transform: The function to transform each message with.
  /// - Returns: The new response.
  @inlinable
  func map<Mapped>(
    _ transform: @escaping @Sendable (Message) throws -> Mapped
  ) -> ClientResponse.Stream<Mapped> {
    switch self.accepted {
    case .success(let contents):
      return ClientResponse.Stream(
        metadata: self.metadata,
        bodyParts: RPCAsyncSequence(
          wrapping: contents.bodyParts.map {
            switch $0 {
            case .message(let message):
              return .message(try transform(message))
            case .trailingMetadata(let metadata):
              return .trailingMetadata(metadata)
            }
          }
        )
      )

    case .failure(let error):
      return ClientResponse.Stream(accepted: .failure(error))
    }
  }
}
