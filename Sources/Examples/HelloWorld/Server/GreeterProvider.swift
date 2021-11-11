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
import HelloWorldModel
import NIOCore

class GreeterProvider: Helloworld_GreeterProvider {
  var interceptors: Helloworld_GreeterServerInterceptorFactoryProtocol?

  func sayHello(
    request: Helloworld_HelloRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Helloworld_HelloReply> {
    let recipient = request.name.isEmpty ? "stranger" : request.name
    let response = Helloworld_HelloReply.with {
      $0.message = "Hello \(recipient)!"
    }
    return context.eventLoop.makeSucceededFuture(response)
  }
}
