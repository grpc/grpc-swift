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

package struct Namer: Sendable, Hashable {
  let grpcCore: String

  package init(grpcCore: String = "GRPCCore") {
    self.grpcCore = grpcCore
  }

  private func grpcCore(_ typeName: String) -> ExistingTypeDescription {
    return .member([self.grpcCore, typeName])
  }

  private func requestResponse(
    for type: String?,
    isRequest: Bool,
    isStreaming: Bool,
    isClient: Bool
  ) -> ExistingTypeDescription {
    let prefix = isStreaming ? "Streaming" : ""
    let peer = isClient ? "Client" : "Server"
    let kind = isRequest ? "Request" : "Response"
    let baseType = self.grpcCore(prefix + peer + kind)

    if let type = type {
      return .generic(wrapper: baseType, wrapped: .member(type))
    } else {
      return baseType
    }
  }

  func literalNamespacedType(_ type: String) -> String {
    return self.grpcCore + "." + type
  }

  func serverRequest(forType type: String?, streaming: Bool) -> ExistingTypeDescription {
    return self.requestResponse(for: type, isRequest: true, isStreaming: streaming, isClient: false)
  }

  func serverResponse(forType type: String?, streaming: Bool) -> ExistingTypeDescription {
    return self.requestResponse(
      for: type,
      isRequest: false,
      isStreaming: streaming,
      isClient: false
    )
  }

  func clientRequest(forType type: String?, streaming: Bool) -> ExistingTypeDescription {
    return self.requestResponse(for: type, isRequest: true, isStreaming: streaming, isClient: true)
  }

  func clientResponse(forType type: String?, streaming: Bool) -> ExistingTypeDescription {
    return self.requestResponse(for: type, isRequest: false, isStreaming: streaming, isClient: true)
  }

  var serverContext: ExistingTypeDescription {
    self.grpcCore("ServerContext")
  }

  func rpcRouter(genericOver type: String) -> ExistingTypeDescription {
    .generic(wrapper: self.grpcCore("RPCRouter"), wrapped: .member(type))
  }

  var serviceDescriptor: ExistingTypeDescription {
    self.grpcCore("ServiceDescriptor")
  }

  var methodDescriptor: ExistingTypeDescription {
    self.grpcCore("MethodDescriptor")
  }

  func serializer(forType type: String) -> ExistingTypeDescription {
    .generic(wrapper: self.grpcCore("MessageSerializer"), wrapped: .member(type))
  }

  func deserializer(forType type: String) -> ExistingTypeDescription {
    .generic(wrapper: self.grpcCore("MessageDeserializer"), wrapped: .member(type))
  }

  func rpcWriter(forType type: String) -> ExistingTypeDescription {
    .generic(wrapper: self.grpcCore("RPCWriter"), wrapped: .member(type))
  }

  func rpcAsyncSequence(forType type: String) -> ExistingTypeDescription {
    .generic(
      wrapper: self.grpcCore("RPCAsyncSequence"),
      wrapped: .member(type),
      .any(.member(["Swift", "Error"]))
    )
  }

  var callOptions: ExistingTypeDescription {
    self.grpcCore("CallOptions")
  }

  var metadata: ExistingTypeDescription {
    self.grpcCore("Metadata")
  }

  func grpcClient(genericOver transport: String) -> ExistingTypeDescription {
    .generic(wrapper: self.grpcCore("GRPCClient"), wrapped: [.member(transport)])
  }
}
