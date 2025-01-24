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

extension ExistingTypeDescription {
  fileprivate static func grpcCore(_ typeName: String) -> Self {
    return .member(["GRPCCore", typeName])
  }

  fileprivate static func requestResponse(
    for type: String?,
    isRequest: Bool,
    isStreaming: Bool,
    isClient: Bool
  ) -> Self {
    let prefix = isStreaming ? "Streaming" : ""
    let peer = isClient ? "Client" : "Server"
    let kind = isRequest ? "Request" : "Response"
    let baseType: Self = .grpcCore(prefix + peer + kind)

    if let type = type {
      return .generic(wrapper: baseType, wrapped: .member(type))
    } else {
      return baseType
    }
  }

  package static func serverRequest(forType type: String?, streaming: Bool) -> Self {
    return .requestResponse(for: type, isRequest: true, isStreaming: streaming, isClient: false)
  }

  package static func serverResponse(forType type: String?, streaming: Bool) -> Self {
    return .requestResponse(for: type, isRequest: false, isStreaming: streaming, isClient: false)
  }

  package static func clientRequest(forType type: String?, streaming: Bool) -> Self {
    return .requestResponse(for: type, isRequest: true, isStreaming: streaming, isClient: true)
  }

  package static func clientResponse(forType type: String?, streaming: Bool) -> Self {
    return .requestResponse(for: type, isRequest: false, isStreaming: streaming, isClient: true)
  }

  package static let serverContext: Self = .grpcCore("ServerContext")

  package static func rpcRouter(genericOver type: String) -> Self {
    .generic(wrapper: .grpcCore("RPCRouter"), wrapped: .member(type))
  }

  package static let serviceDescriptor: Self = .grpcCore("ServiceDescriptor")
  package static let methodDescriptor: Self = .grpcCore("MethodDescriptor")

  package static func serializer(forType type: String) -> Self {
    .generic(wrapper: .grpcCore("MessageSerializer"), wrapped: .member(type))
  }

  package static func deserializer(forType type: String) -> Self {
    .generic(wrapper: .grpcCore("MessageDeserializer"), wrapped: .member(type))
  }

  package static func rpcWriter(forType type: String) -> Self {
    .generic(wrapper: .grpcCore("RPCWriter"), wrapped: .member(type))
  }

  package static func rpcAsyncSequence(forType type: String) -> Self {
    .generic(
      wrapper: .grpcCore("RPCAsyncSequence"),
      wrapped: .member(type),
      .any(.member(["Swift", "Error"]))
    )
  }

  package static let callOptions: Self = .grpcCore("CallOptions")
  package static let metadata: Self = .grpcCore("Metadata")

  package static func grpcClient(genericOver transport: String) -> Self {
    .generic(wrapper: .grpcCore("GRPCClient"), wrapped: [.member(transport)])
  }
}
