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
import Foundation
import GRPCCore

struct HelloWorld: RegistrableRPCService {
  static let serviceDescriptor = ServiceDescriptor(package: "helloworld", service: "HelloWorld")

  func sayHello(
    _ request: ServerRequest<[UInt8]>
  ) async throws -> ServerResponse<[UInt8]> {
    let name = String(bytes: request.message, encoding: .utf8) ?? "world"
    return ServerResponse(message: Array("Hello, \(name)!".utf8), metadata: [])
  }

  func registerMethods(with router: inout RPCRouter) {
    let serializer = IdentitySerializer()
    let deserializer = IdentityDeserializer()

    router.registerHandler(
      forMethod: Methods.sayHello,
      deserializer: deserializer,
      serializer: serializer
    ) { streamRequest, context in
      let singleRequest = try await ServerRequest(stream: streamRequest)
      let singleResponse = try await self.sayHello(singleRequest)
      return StreamingServerResponse(single: singleResponse)
    }
  }

  enum Methods {
    static let sayHello = MethodDescriptor(
      fullyQualifiedService: HelloWorld.serviceDescriptor.fullyQualifiedService,
      method: "SayHello"
    )
  }
}
