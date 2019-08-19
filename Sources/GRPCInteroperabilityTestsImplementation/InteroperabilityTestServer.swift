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
import GRPC
import NIO
import NIOSSL

/// Makes a server for gRPC interoperability testing.
///
/// - Parameters:
///   - host: The host to bind the server socket to, defaults to "localhost".
///   - port: The port to bind the server socket to.
///   - eventLoopGroup: Event loop group to run the server on.
///   - serviceProviders: Service providers to handle requests with, defaults to provider for the
///     "Test" service.
///   - useTLS: Whether to use TLS or not. If `true` then the server will use the "server1"
///     certificate and CA as set out in the interoperability test specification. The common name
///     is "*.test.google.fr"; clients should set their hostname override accordingly.
/// - Returns: A future `Server` configured to serve the test service.
public func makeInteroperabilityTestServer(
  host: String = "localhost",
  port: Int,
  eventLoopGroup: EventLoopGroup,
  serviceProviders: [CallHandlerProvider] = [TestServiceProvider()],
  useTLS: Bool
) throws -> EventLoopFuture<Server> {
  var configuration = Server.Configuration(
    target: .hostAndPort(host, port),
    eventLoopGroup: eventLoopGroup,
    serviceProviders: serviceProviders)

  if useTLS {
    print("Using the gRPC interop testing CA for TLS; clients should expect the host to be '*.test.google.fr'")

    let caCert = InteroperabilityTestCredentials.caCertificate
    let serverCert = InteroperabilityTestCredentials.server1Certificate
    let serverKey = InteroperabilityTestCredentials.server1Key

    configuration.tls = .init(
      certificateChain: [.certificate(serverCert)],
      privateKey: .privateKey(serverKey),
      trustRoots: .certificates([caCert])
    )
  }

  return Server.start(configuration: configuration)
}
