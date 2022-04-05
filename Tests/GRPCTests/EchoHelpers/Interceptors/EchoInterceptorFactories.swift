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
import EchoModel
import GRPC

// MARK: - Client

internal final class EchoClientInterceptors: Echo_EchoClientInterceptorFactoryProtocol {
  #if swift(>=5.6)
  internal typealias Factory = @Sendable ()
    -> ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>
  #else
  internal typealias Factory = () -> ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>
  #endif // swift(>=5.6)
  private let factories: [Factory]

  internal init(_ factories: Factory...) {
    self.factories = factories
  }

  private func makeInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.factories.map { $0() }
  }

  func makeGetInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeExpandInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeCollectInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeUpdateInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }
}

// MARK: - Server

internal final class EchoServerInterceptors: Echo_EchoServerInterceptorFactoryProtocol {
  internal typealias Factory = () -> ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>
  private var factories: [Factory] = []

  internal init(_ factories: Factory...) {
    self.factories = factories
  }

  internal func register(_ factory: @escaping Factory) {
    self.factories.append(factory)
  }

  private func makeInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.factories.map { $0() }
  }

  func makeGetInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeExpandInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeCollectInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }

  func makeUpdateInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.makeInterceptors()
  }
}
