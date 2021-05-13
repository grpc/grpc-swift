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

internal protocol ConnectionManagerConnectivityDelegate {
  /// The state of the connection changed.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager reporting the change of state.
  ///   - oldState: The previous `ConnectivityState`.
  ///   - newState: The current `ConnectivityState`.
  func connectionStateDidChange(
    _ connectionManager: ConnectionManager,
    from oldState: ConnectivityState,
    to newState: ConnectivityState
  )

  /// The connection is quiescing.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager whose connection is quiescing.
  func connectionIsQuiescing(_ connectionManager: ConnectionManager)
}

internal protocol ConnectionManagerHTTP2Delegate {
  /// An HTTP/2 stream was closed.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager reporting the closed stream.
  func streamClosed(_ connectionManager: ConnectionManager)

  /// The connection received a SETTINGS frame containing SETTINGS_MAX_CONCURRENT_STREAMS.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager which received the settings update.
  ///   - maxConcurrentStreams: The value of SETTINGS_MAX_CONCURRENT_STREAMS.
  func receivedSettingsMaxConcurrentStreams(
    _ connectionManager: ConnectionManager,
    maxConcurrentStreams: Int
  )
}
