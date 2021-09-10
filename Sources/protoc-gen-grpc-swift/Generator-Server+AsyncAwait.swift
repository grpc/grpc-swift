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
import SwiftProtobuf
import SwiftProtobufPluginLibrary

// MARK: - Protocol

extension Generator {
  internal func printServerProtocolAsyncAwait() {
    let sourceComments = self.service.protoSourceComments()
    if !sourceComments.isEmpty {
      // Source comments already have the leading '///'
      self.println(sourceComments, newline: false)
      self.println("///")
    }
    self.println("/// To implement a server, implement an object which conforms to this protocol.")
    self.printAvailabilityForAsyncAwait()
    self.withIndentation(
      "\(self.access) protocol \(self.asyncProviderName): CallHandlerProvider",
      braces: .curly
    ) {
      self.println("var interceptors: \(self.serverInterceptorProtocolName)? { get }")

      for method in service.methods {
        self.method = method
        self.println()
        self.printRPCProtocolRequirement()
      }
    }
  }

  fileprivate func printRPCProtocolRequirement() {
    // Print any comments; skip the newline as source comments include them already.
    self.println(self.method.protoSourceComments(), newline: false)

    let arguments: [String]
    let returnType: String?

    switch streamingType(self.method) {
    case .unary:
      arguments = [
        "request: \(self.methodInputName)",
        "context: \(Types.serverContext)",
      ]
      returnType = self.methodOutputName

    case .clientStreaming:
      arguments = [
        "requests: \(Types.requestStream(of: self.methodInputName))",
        "context: \(Types.serverContext)",
      ]
      returnType = self.methodOutputName

    case .serverStreaming:
      arguments = [
        "request: \(self.methodInputName)",
        "responseStream: \(Types.responseStreamWriter(of: self.methodOutputName))",
        "context: \(Types.serverContext)",
      ]
      returnType = nil

    case .bidirectionalStreaming:
      arguments = [
        "requests: \(Types.requestStream(of: self.methodInputName))",
        "responseStream: \(Types.responseStreamWriter(of: self.methodOutputName))",
        "context: \(Types.serverContext)",
      ]
      returnType = nil
    }

    self.printFunction(
      name: self.methodFunctionName,
      arguments: arguments,
      returnType: returnType,
      sendable: true,
      async: true,
      throws: true,
      bodyBuilder: nil
    )
  }
}

// MARK: - Protocol Extension; RPC handling

extension Generator {
  internal func printServerProtocolExtensionAsyncAwait() {
    // Default extension to provide the service name and routing for methods.
    self.printAvailabilityForAsyncAwait()
    self.withIndentation("extension \(self.asyncProviderName)", braces: .curly) {
      self.withIndentation("\(self.access) var serviceName: Substring", braces: .curly) {
        self.println("return \"\(self.servicePath)\"")
      }

      self.println()

      // Default nil interceptor factory.
      self.withIndentation(
        "\(self.access) var interceptors: \(self.serverInterceptorProtocolName)?",
        braces: .curly
      ) {
        self.println("return nil")
      }

      self.println()

      self.printFunction(
        name: "handle",
        arguments: [
          "method name: Substring",
          "context: CallHandlerContext",
        ],
        returnType: "GRPCServerHandlerProtocol?",
        access: self.access
      ) {
        self.println("switch name {")
        for method in self.service.methods {
          self.method = method

          let requestType = self.methodInputName
          let responseType = self.methodOutputName
          let interceptorFactory = self.methodInterceptorFactoryName
          let functionName = self.methodFunctionName

          self.withIndentation("case \"\(self.method.name)\":", braces: .none) {
            self.withIndentation("return \(Types.serverHandler)", braces: .round) {
              self.println("context: context,")
              self.println("requestDeserializer: \(Types.deserializer(for: requestType))(),")
              self.println("responseSerializer: \(Types.serializer(for: responseType))(),")
              self.println("interceptors: self.interceptors?.\(interceptorFactory)() ?? [],")
              switch streamingType(self.method) {
              case .unary:
                self.println("wrapping: self.\(functionName)(request:context:)")

              case .clientStreaming:
                self.println("wrapping: self.\(functionName)(requests:context:)")

              case .serverStreaming:
                self.println("wrapping: self.\(functionName)(request:responseStream:context:)")

              case .bidirectionalStreaming:
                self.println("wrapping: self.\(functionName)(requests:responseStream:context:)")
              }
            }
          }
        }

        // Default case.
        self.println("default:")
        self.withIndentation {
          self.println("return nil")
        }

        self.println("}") // switch
      }
    }
  }
}
