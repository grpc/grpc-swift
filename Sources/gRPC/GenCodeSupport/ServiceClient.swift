/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

import Dispatch
import Foundation
import SwiftProtobuf

public protocol ServiceClient {
  var channel: Channel { get }

  /// This metadata will be sent with all requests.
  var metadata: Metadata { get }

  /// This property allows the service host name to be overridden.
  /// For example, it can be used to make calls to "localhost:8080"
  /// appear to be to "example.com".
  var host: String { get }

  /// This property allows the service timeout to be overridden.
  var timeout: TimeInterval { get }
}

open class ServiceClientBase: ServiceClient {
  public let channel: Channel

  public var metadata: Metadata

  public var host: String {
    get { return channel.host }
    set { channel.host = newValue }
  }

  public var timeout: TimeInterval {
    get { return channel.timeout }
    set { channel.timeout = newValue }
  }

  /// Create a client.
  public init(address: String, secure: Bool = true) {
    gRPC.initialize()
    channel = Channel(address: address, secure: secure)
    metadata = Metadata()
  }

  /// Create a client that makes secure connections with a custom certificate and (optional) hostname.
  public init(address: String, certificates: String, host: String?) {
    gRPC.initialize()
    channel = Channel(address: address, certificates: certificates, host: host)
    metadata = Metadata()
  }
}

/// Simple fake implementation of ServiceClient that returns a previously-defined set of results
/// and stores request values passed into it for later verification.
/// Note: completion blocks are NOT called with this default implementation, and asynchronous unary calls are NOT implemented!
open class ServiceClientTestStubBase: ServiceClient {
  open private(set) var channel: Channel

  open var metadata: Metadata

  open var host: String {
    get { return self.channel.host }
    set { self.channel.host = newValue }
  }

  open var timeout: TimeInterval {
    get { return channel.timeout }
    set { channel.timeout = newValue }
  }

  /// Create a client.
  public init(address: String, secure: Bool = true) {
    gRPC.initialize()
    channel = Channel(address: address, secure: secure)
    metadata = Metadata()
  }

  /// Create a client that makes secure connections with a custom certificate and (optional) hostname.
  public init(address: String, certificates: String, host: String?) {
    gRPC.initialize()
    channel = Channel(address: address, certificates: certificates, host: host)
    metadata = Metadata()
  }
}
