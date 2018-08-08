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

public protocol ServiceClient: class {
  var channel: Channel { get }

  /// This metadata will be sent with all requests.
  var metadata: Metadata { get set }

  /// This property allows the service host name to be overridden.
  /// For example, it can be used to make calls to "localhost:8080"
  /// appear to be to "example.com".
  var host: String { get set }

  /// This property allows the service timeout to be overridden.
  var timeout: TimeInterval { get set }
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
  required public init(address: String, secure: Bool = true, arguments: [Channel.Argument] = []) {
    gRPC.initialize()
    channel = Channel(address: address, secure: secure, arguments: arguments)
    metadata = Metadata()
  }

  /// Create a client using a pre-defined channel.
  required public init(channel: Channel) {
    self.channel = channel
    metadata = Metadata()
  }

  /// Create a client with Google credentials suitable for connecting to a Google-provided API.
  /// gRPC protobuf defnitions for use with this method are here: https://github.com/googleapis/googleapis
  /// - Parameter googleAPI: the name of the Google API service (e.g. "cloudkms" in "cloudkms.googleapis.com")
  /// - Parameter arguments: list of channel configuration options
  ///
  /// Note: CgRPC's `grpc_google_default_credentials_create` doesn't accept a root pem argument.
  /// To override: `export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/path/to/your/root/cert.pem`
  required public init(googleAPI: String, arguments: [Channel.Argument] = []) {
    gRPC.initialize()

    // Force the address of the Google API to account for the security concern mentioned in
    // Sources/CgRPC/include/grpc/grpc_security.h:
    //    WARNING: Do NOT use this credentials to connect to a non-google service as
    //    this could result in an oauth2 token leak.
    let address = googleAPI + ".googleapis.com"
    channel = Channel(googleAddress: address, arguments: arguments)
    metadata = Metadata()
  }

  /// Create a client that makes secure connections with a custom certificate.
  required public init(address: String, certificates: String, clientCertificates: String? = nil, clientKey: String? = nil, arguments: [Channel.Argument] = []) {
    gRPC.initialize()
    channel = Channel(address: address, certificates: certificates, clientCertificates: clientCertificates, clientKey: clientKey, arguments: arguments)
    metadata = Metadata()
  }
}

/// Simple fake implementation of ServiceClient that returns a previously-defined set of results
/// and stores request values passed into it for later verification.
/// Note: completion blocks are NOT called with this default implementation, and asynchronous unary calls are NOT implemented!
open class ServiceClientTestStubBase: ServiceClient {
  open var channel: Channel { fatalError("not implemented") }
  open var metadata = Metadata()
  open var host = ""
  open var timeout: TimeInterval = 0

  public init() {}
}
