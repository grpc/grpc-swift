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
#if compiler(>=5.6)
import GRPC
import HelloWorldModel
import NIOCore

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class GreeterProvider: Helloworld_GreeterAsyncProvider {
  let interceptors: Helloworld_GreeterServerInterceptorFactoryProtocol? = nil

  func sayHello(
    request: Helloworld_HelloRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Helloworld_HelloReply {
    let recipient = request.name.isEmpty ? "stranger" : request.name
    return Helloworld_HelloReply.with {
      $0.message = "Hello \(recipient)!"
    }
  }
}
#endif // compiler(>=5.6)
