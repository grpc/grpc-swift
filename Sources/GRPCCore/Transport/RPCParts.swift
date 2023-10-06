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

/// Part of a request sent from a client to a server in a stream.
public enum RPCRequestPart: Hashable, Sendable {
  /// Key-value pairs sent at the start of a request stream. Only one ``metadata(_:)`` value may
  /// be sent to the server.
  case metadata(Metadata)

  /// The bytes of a serialized message to send to the server. A stream may have any number of
  /// messages sent on it. Restrictions for unary request or response streams are imposed at a
  /// higher level.
  case message([UInt8])
}

/// Part of a response sent from a server to a client in a stream.
public enum RPCResponsePart: Hashable, Sendable {
  /// Key-value pairs sent at the start of the response stream. At most one ``metadata(_:)`` value
  /// may be sent to the client. If the server sends ``metadata(_:)`` it must be the first part in
  /// the response stream.
  case metadata(Metadata)

  /// The bytes of a serialized message to send to the client. A stream may have any number of
  /// messages sent on it. Restrictions for unary request or response streams are imposed at a
  /// higher level.
  case message([UInt8])

  /// A status and key-value pairs sent to the client at the end of the response stream. Every
  /// response stream must have exactly one ``status(_:_:)`` as the final part of the request
  /// stream.
  case status(Status, Metadata)
}
