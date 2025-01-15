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

/// A context passed to the client containing additional information about the RPC.
public struct ClientContext: Sendable {
  /// A description of the method being called.
  public var descriptor: MethodDescriptor

  /// A description of the remote peer.
  ///
  /// The format of the description should follow the pattern "<transport>:<address>" where
  /// "<transport>" indicates the underlying network transport (such as "ipv4", "unix", or
  /// "in-process"). This is a guideline for how descriptions should be formatted; different
  /// implementations may not follow this format so you shouldn't make assumptions based on it.
  ///
  /// Some examples include:
  /// - "ipv4:127.0.0.1:31415",
  /// - "ipv6:[::1]:443",
  /// - "in-process:27182".
  public var remotePeer: String

  /// The hostname of the RPC server.
  public var serverHostname: String

  /// A description of the local peer.
  ///
  /// The format of the description should follow the pattern "<transport>:<address>" where
  /// "<transport>" indicates the underlying network transport (such as "ipv4", "unix", or
  /// "in-process"). This is a guideline for how descriptions should be formatted; different
  /// implementations may not follow this format so you shouldn't make assumptions based on it.
  ///
  /// Some examples include:
  /// - "ipv4:127.0.0.1:31415",
  /// - "ipv6:[::1]:443",
  /// - "in-process:27182".
  public var localPeer: String

  /// The transport in use (e.g. "tcp", "udp").
  public var networkTransportMethod: String

  /// Create a new client interceptor context.
  public init(
    descriptor: MethodDescriptor,
    remotePeer: String,
    localPeer: String,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.descriptor = descriptor
    self.remotePeer = remotePeer
    self.localPeer = localPeer
    self.serverHostname = serverHostname
    self.networkTransportMethod = networkTransportMethod
  }
}
