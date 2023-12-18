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

struct ClientCodeTranslator: SpecializedTranslator {
  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    let codeBlocks = [CodeBlock]()
    
    for service in codeGenerationRequest.services {
      
    }
    return codeBlocks
  }
}

extension ClientCodeTranslator {
  private func makeClientProtocol(for service: CodeGenerationRequest.ServiceDescriptor, in codeGenerationRequest: CodeGenerationRequest) -> Declaration {
    var methods = [Declaration]()
    for method in service.methods {
      methods.append(self.makeSerializerDeserializerMethod(for: method, in: service, from: codeGenerationRequest))
    }
  
    let clientProtocol = Declaration.protocol(ProtocolDescription(name: self.clientProtocolName(for: service), conformances: ["Sendable"], members: methods))
    return clientProtocol
  }
  
  private func makeSerializerDeserializerMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let methodParameters = self.makeParameters(for: method, in: service, from: codeGenerationRequest)
    let functionSignature =  FunctionSignatureDescription(kind: .function(name: method.name, isStatic: false, genericType: "R", conformances: ["Sendable"]), parameters: methodParameters)
    
    let methodDeclaration = Declaration.function(signature: functionSignature)
    return methodDeclaration
  }
  
  private func makeParameters(for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor, in service: CodeGenerationRequest.ServiceDescriptor, from codeGenerationRequest: CodeGenerationRequest) -> [ParameterDescription] {
    var arguments = [ParameterDescription]()
    
    arguments.append(self.clientRequestParameter(isInputStreaming: method.isInputStreaming, serviceName: service.name))
    arguments.append(self.serializerParameter(serviceName: service.name))
    arguments.append(self.deserializerParameter(serviceName: service.name))
    return arguments
  }
  private func clientRequestParameter(isInputStreaming: Bool, serviceName: String) -> ParameterDescription {
      let clientRequestType = isInputStreaming ? ExistingTypeDescription.member(["ClientRequest", "Stream"]) : ExistingTypeDescription.member(["ClientRequest", "Single"])
    return ParameterDescription(label: "request", type: .generic(wrapper: clientRequestType, wrapped: .member([serviceName, "Request"])))
  }
  
  private func serializerParameter(serviceName: String) -> ParameterDescription {
    return ParameterDescription(label: "serializer", type: .some(.generic(wrapper: .member("MessageSerializer"), wrapped: .member([serviceName, "Request"]))))
  }
  
  private func deserializerParameter(serviceName: String) -> ParameterDescription {
    return ParameterDescription(label: "deserializer", type: .some(.generic(wrapper: .member("MessageDeserializer"), wrapped: .member([serviceName, "Response"]))))
  }
  
  private func bodyParameter(serviceName: String, isOutputStreaming: Bool) -> ParameterDescription {
    let bodyClosure = 
    return ParameterDescription(name: "body", type: .)
  }
  
  private func clientResponseType(isOutputStreaming: Bool, serviceName: String) -> ExistingTypeDescription {
      let clientRequestType = isOutputStreaming ? ExistingTypeDescription.member(["ClientResponse", "Stream"]) : ExistingTypeDescription.member(["ClientRequest", "Single"])
    return .generic(wrapper: clientRequestType, wrapped: .member([serviceName, "Request"]))
  }

  private func clientProtocolName(for service: CodeGenerationRequest.ServiceDescriptor) -> String {
    let name: String
    if service.namespace.isEmpty {
      name = "\(service.name)ClientProtocol"
    } else {
      name = "\(service.namespace)_\(service.name)ClientProtocol"
    }
    
    return name
  }
}
