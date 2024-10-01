/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import GRPCCore
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct BinaryEcho: RegistrableRPCService {
  func get(
    _ request: ServerRequest<[UInt8]>
  ) async throws -> ServerResponse<[UInt8]> {
    ServerResponse(message: request.message, metadata: request.metadata)
  }

  func collect(
    _ request: StreamingServerRequest<[UInt8]>
  ) async throws -> ServerResponse<[UInt8]> {
    let collected = try await request.messages.reduce(into: []) { $0.append(contentsOf: $1) }
    return ServerResponse(message: collected, metadata: request.metadata)
  }

  func expand(
    _ request: ServerRequest<[UInt8]>
  ) async throws -> StreamingServerResponse<[UInt8]> {
    return StreamingServerResponse(metadata: request.metadata) {
      for byte in request.message {
        try await $0.write([byte])
      }
      return [:]
    }
  }

  func update(
    _ request: StreamingServerRequest<[UInt8]>
  ) async throws -> StreamingServerResponse<[UInt8]> {
    return StreamingServerResponse(metadata: request.metadata) {
      for try await message in request.messages {
        try await $0.write(message)
      }
      return [:]
    }
  }

  func registerMethods(with router: inout RPCRouter) {
    let serializer = IdentitySerializer()
    let deserializer = IdentityDeserializer()

    router.registerHandler(
      forMethod: Methods.get,
      deserializer: deserializer,
      serializer: serializer
    ) { streamRequest, context in
      let singleRequest = try await ServerRequest(stream: streamRequest)
      let singleResponse = try await self.get(singleRequest)
      return StreamingServerResponse(single: singleResponse)
    }

    router.registerHandler(
      forMethod: Methods.collect,
      deserializer: deserializer,
      serializer: serializer
    ) { streamRequest, context in
      let singleResponse = try await self.collect(streamRequest)
      return StreamingServerResponse(single: singleResponse)
    }

    router.registerHandler(
      forMethod: Methods.expand,
      deserializer: deserializer,
      serializer: serializer
    ) { streamRequest, context in
      let singleRequest = try await ServerRequest(stream: streamRequest)
      let streamResponse = try await self.expand(singleRequest)
      return streamResponse
    }

    router.registerHandler(
      forMethod: Methods.update,
      deserializer: deserializer,
      serializer: serializer
    ) { streamRequest, context in
      let streamResponse = try await self.update(streamRequest)
      return streamResponse
    }
  }

  enum Methods {
    static let get = MethodDescriptor(service: "echo.Echo", method: "Get")
    static let collect = MethodDescriptor(service: "echo.Echo", method: "Collect")
    static let expand = MethodDescriptor(service: "echo.Echo", method: "Expand")
    static let update = MethodDescriptor(service: "echo.Echo", method: "Update")
  }
}
