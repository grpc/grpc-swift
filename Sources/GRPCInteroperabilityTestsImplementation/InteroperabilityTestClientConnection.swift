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
import GRPC
import NIOCore
import NIOSSL

public func makeInteroperabilityTestClientBuilder(
  group: EventLoopGroup,
  useTLS: Bool
) -> ClientConnection.Builder {
  let builder: ClientConnection.Builder

  if useTLS {
    // The CA certificate has a common name of "*.test.google.fr", use the following host override
    // so we can do full certificate verification.
    builder = ClientConnection.usingTLSBackedByNIOSSL(on: group)
      .withTLS(trustRoots: .certificates([InteroperabilityTestCredentials.caCertificate]))
      .withTLS(serverHostnameOverride: "foo.test.google.fr")
  } else {
    builder = ClientConnection.insecure(group: group)
  }

  return builder
}
