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

enum ConnectivityState: Sendable, Hashable {
  /// This channel isn't trying to create a connection because of a lack of new or pending RPCs.
  ///
  /// New streams may be created in this state. Doing so will cause the channel to enter the
  /// connecting state.
  case idle

  /// The channel is trying to establish a connection and is waiting to make progress on one of the
  /// steps involved in name resolution, TCP connection establishment or TLS handshake.
  case connecting

  /// The channel has successfully established a connection all the way through TLS handshake (or
  /// equivalent) and protocol-level (HTTP/2, etc) handshaking.
  case ready

  /// There has been some transient failure (such as a TCP 3-way handshake timing out or a socket
  /// error). Channels in this state will eventually switch to the ``connecting`` state and try to
  /// establish a connection again. Since retries are done with exponential backoff, channels that
  /// fail to connect will start out spending very little time in this state but as the attempts
  /// fail repeatedly, the channel will spend increasingly large amounts of time in this state.
  case transientFailure

  /// This channel has started shutting down. Any new RPCs should fail immediately. Pending RPCs
  /// may continue running until the application cancels them. Channels may enter this state either
  /// because the application explicitly requested a shutdown or if a non-recoverable error has
  /// happened during attempts to connect. Channels that have entered this state will never leave
  /// this state.
  case shutdown
}
