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
import Foundation
import SwiftGRPCNIO
import NIO
import NIOSSL

/// Makes a client connections for gRPC interopability testing.
///
/// - Parameters:
///   - host: The host to connect to.
///   - port: The port to connect to.
///   - eventLoopGroup: Event loop group to run client connection on.
///   - useTLS: Whether to use TLS or not.
///   - caCertificate: The root certificate to use for TLS, this defaults to the self-signed
///     certificate listed in the interopability test specification which has a common name of
///     "*.test.google.fr". Ignored if `useTLS` is false.
///   - hostnameOverride: Expected hostname for the server; this defaults to "foo.test.google.fr" to
///     support the default CA certificate used for these tests. Ignored if `useTLS` is false.
/// - Returns: A future of a `GRPCClientConnection`.
public func makeInteropabilityTestClientConnection(
  host: String,
  port: Int,
  eventLoopGroup: EventLoopGroup,
  useTLS: Bool,
  caCertificate: NIOSSLCertificate = InteropabilityTestCredentials.caCertificate,
  hostnameOverride: String? = "foo.test.google.fr"
) throws -> EventLoopFuture<GRPCClientConnection> {
  let tlsMode: GRPCClientConnection.TLSMode

  if useTLS {
    let tlsConfiguration = TLSConfiguration.forClient(
      trustRoots: .certificates([caCertificate]),
      applicationProtocols: ["h2"])

    tlsMode = .custom(try NIOSSLContext(configuration: tlsConfiguration))
  } else {
    tlsMode = .none
  }

  return try GRPCClientConnection.start(
    host: host,
    port: port,
    eventLoopGroup: eventLoopGroup,
    tls: tlsMode,
    hostnameOverride: hostnameOverride
  )
}
