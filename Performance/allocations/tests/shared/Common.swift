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
import GRPC
import NIO

func makeEchoServer(
  group: EventLoopGroup,
  host: String = "127.0.0.1",
  port: Int = 0,
  interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil
) -> EventLoopFuture<Server> {
  return Server.insecure(group: group)
    .withServiceProviders([MinimalEchoProvider(interceptors: interceptors)])
    .bind(host: host, port: port)
}

func makeClientConnection(
  group: EventLoopGroup,
  host: String = "127.0.0.1",
  port: Int
) -> ClientConnection {
  return ClientConnection.insecure(group: group)
    .connect(host: host, port: port)
}

func makeEchoClientInterceptors(count: Int) -> Echo_EchoClientInterceptorFactoryProtocol? {
  let factory = EchoClientInterceptors()
  for _ in 0 ..< count {
    factory.register { NoOpEchoClientInterceptor() }
  }
  return factory
}

func makeEchoServerInterceptors(count: Int) -> Echo_EchoServerInterceptorFactoryProtocol? {
  let factory = EchoServerInterceptors()
  for _ in 0 ..< count {
    factory.register { NoOpEchoServerInterceptor() }
  }
  return factory
}

final class EchoClientInterceptors: Echo_EchoClientInterceptorFactoryProtocol {
  internal typealias Factory = () -> ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>
  private var factories: [Factory] = []

  internal init(_ factories: Factory...) {
    self.factories = factories
  }

  internal func register(_ factory: @escaping Factory) {
    self.factories.append(factory)
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

final class NoOpEchoClientInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {}
final class NoOpEchoServerInterceptor: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse> {}
