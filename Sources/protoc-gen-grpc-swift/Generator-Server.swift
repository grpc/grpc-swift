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
    self.printServerProtocol()
  }

  private func printServerProtocol() {
    println("/// To build a server, implement a class that conforms to this protocol.")
    println("\(access) protocol \(providerName): CallHandlerProvider {")
    indent()
    for method in service.methods {
      self.method = method

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
    outdent()
    println("}")
    println()
    println("extension \(providerName) {")
    indent()
    println("\(access) var serviceName: Substring { return \"\(servicePath)\" }")
    println()
    println(
      "/// Determines, calls and returns the appropriate request handler, depending on the request's method."
    )
    println("/// Returns nil for methods not handled by this service.")
    println(
      "\(access) func handleMethod(_ methodName: Substring, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {"
    )
    indent()
    println("switch methodName {")
    for method in service.methods {
      self.method = method
      println("case \"\(method.name)\":")
      indent()
      let callHandlerType: String
      switch streamingType(method) {
      case .unary: callHandlerType = "CallHandlerFactory.makeUnary"
      case .serverStreaming: callHandlerType = "CallHandlerFactory.makeServerStreaming"
      case .clientStreaming: callHandlerType = "CallHandlerFactory.makeClientStreaming"
      case .bidirectionalStreaming: callHandlerType =
        "CallHandlerFactory.makeBidirectionalStreaming"
      }
      println("return \(callHandlerType)(callHandlerContext: callHandlerContext) { context in")
      indent()
      switch streamingType(method) {
      case .unary, .serverStreaming:
        println("return { request in")
        indent()
        println("self.\(methodFunctionName)(request: request, context: context)")
        outdent()
        println("}")
      case .clientStreaming, .bidirectionalStreaming:
        println("return self.\(methodFunctionName)(context: context)")
      }
      outdent()
      println("}")
      outdent()
      println()
    }
    println("default: return nil")
    println("}")
    outdent()
    println("}")

    outdent()
    println("}")
    println()
  }
}
