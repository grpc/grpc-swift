/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import SwiftProtobuf
import SwiftProtobufPluginLibrary

extension Generator {
  internal func printServer() {
    if self.options.generateServer {
      self.printServerProtocol()
      self.println()
      self.printServerProtocolExtension()
      self.println()
      self.printIfCompilerGuardForAsyncAwait()
      self.println()
      self.printServerProtocolAsyncAwait()
      self.println()
      self.printServerProtocolExtensionAsyncAwait()
      self.println()
      self.printEndCompilerGuardForAsyncAwait()
      self.println()
      // Both implementations share definitions for interceptors and metadata.
      self.printServerInterceptorFactoryProtocol()
      self.println()
      self.printServerMetadata()
    }
  }

  private func printServerProtocol() {
    let comments = self.service.protoSourceComments()
    if !comments.isEmpty {
      // Source comments already have the leading '///'
      self.println(comments, newline: false)
      self.println("///")
    }
    println("/// To build a server, implement a class that conforms to this protocol.")
    println("\(access) protocol \(providerName): CallHandlerProvider {")
    self.withIndentation {
      println("var interceptors: \(self.serverInterceptorProtocolName)? { get }")
      for method in service.methods {
        self.method = method
        self.println()

        switch streamingType(method) {
        case .unary:
          println(self.method.protoSourceComments(), newline: false)
          println(
            "func \(methodFunctionName)(request: \(methodInputName), context: StatusOnlyCallContext) -> EventLoopFuture<\(methodOutputName)>"
          )
        case .serverStreaming:
          println(self.method.protoSourceComments(), newline: false)
          println(
            "func \(methodFunctionName)(request: \(methodInputName), context: StreamingResponseCallContext<\(methodOutputName)>) -> EventLoopFuture<GRPCStatus>"
          )
        case .clientStreaming:
          println(self.method.protoSourceComments(), newline: false)
          println(
            "func \(methodFunctionName)(context: UnaryResponseCallContext<\(methodOutputName)>) -> EventLoopFuture<(StreamEvent<\(methodInputName)>) -> Void>"
          )
        case .bidirectionalStreaming:
          println(self.method.protoSourceComments(), newline: false)
          println(
            "func \(methodFunctionName)(context: StreamingResponseCallContext<\(methodOutputName)>) -> EventLoopFuture<(StreamEvent<\(methodInputName)>) -> Void>"
          )
        }
      }
    }
    println("}")
  }

  private func printServerProtocolExtension() {
    self.println("extension \(self.providerName) {")
    self.withIndentation {
      self.withIndentation("\(self.access) var serviceName: Substring", braces: .curly) {
        /// This API returns a Substring (hence the '[...]')
        self.println("return \(self.serviceServerMetadata).serviceDescriptor.fullName[...]")
      }
      self.println()
      self.println(
        "/// Determines, calls and returns the appropriate request handler, depending on the request's method."
      )
      self.println("/// Returns nil for methods not handled by this service.")
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
          self.println("case \"\(method.name)\":")
          self.withIndentation {
            // Get the factory name.
            let callHandlerType: String
            switch streamingType(method) {
            case .unary:
              callHandlerType = "UnaryServerHandler"
            case .serverStreaming:
              callHandlerType = "ServerStreamingServerHandler"
            case .clientStreaming:
              callHandlerType = "ClientStreamingServerHandler"
            case .bidirectionalStreaming:
              callHandlerType = "BidirectionalStreamingServerHandler"
            }

            self.println("return \(callHandlerType)(")
            self.withIndentation {
              self.println("context: context,")
              self.println("requestDeserializer: ProtobufDeserializer<\(self.methodInputName)>(),")
              self.println("responseSerializer: ProtobufSerializer<\(self.methodOutputName)>(),")
              self.println(
                "interceptors: self.interceptors?.\(self.methodInterceptorFactoryName)() ?? [],"
              )
              switch streamingType(method) {
              case .unary, .serverStreaming:
                self.println("userFunction: self.\(self.methodFunctionName)(request:context:)")
              case .clientStreaming, .bidirectionalStreaming:
                self.println("observerFactory: self.\(self.methodFunctionName)(context:)")
              }
            }
            self.println(")")
          }
          self.println()
        }

        // Default case.
        self.println("default:")
        self.withIndentation {
          self.println("return nil")
        }
        self.println("}")
      }
    }
    self.println("}")
  }

  private func printServerInterceptorFactoryProtocol() {
    self.println("\(self.access) protocol \(self.serverInterceptorProtocolName) {")
    self.withIndentation {
      // Method specific interceptors.
      for method in service.methods {
        self.println()
        self.method = method
        self.println(
          "/// - Returns: Interceptors to use when handling '\(self.methodFunctionName)'."
        )
        self.println("///   Defaults to calling `self.makeInterceptors()`.")
        // Skip the access, we're defining a protocol.
        self.printMethodInterceptorFactory(access: nil)
      }
    }
    self.println("}")
  }

  private func printMethodInterceptorFactory(
    access: String?,
    bodyBuilder: (() -> Void)? = nil
  ) {
    self.printFunction(
      name: self.methodInterceptorFactoryName,
      arguments: [],
      returnType: "[ServerInterceptor<\(self.methodInputName), \(self.methodOutputName)>]",
      access: access,
      bodyBuilder: bodyBuilder
    )
  }

  func printServerInterceptorFactoryProtocolExtension() {
    self.println("extension \(self.serverInterceptorProtocolName) {")
    self.withIndentation {
      // Default interceptor factory.
      self.printFunction(
        name: "makeInterceptors<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>",
        arguments: [],
        returnType: "[ServerInterceptor<Request, Response>]",
        access: self.access
      ) {
        self.println("return []")
      }

      for method in self.service.methods {
        self.println()

        self.method = method
        self.printMethodInterceptorFactory(access: self.access) {
          self.println("return self.makeInterceptors()")
        }
      }
    }
    self.println("}")
  }
}
