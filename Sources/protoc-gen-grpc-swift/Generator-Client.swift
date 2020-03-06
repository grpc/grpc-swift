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
  internal func printClient() {
    println()
    printServiceClientProtocol()
    println()
    printServiceClientImplementation()
  }

  private func printServiceClientProtocol() {
    println("/// Usage: instantiate \(clientClassName), then call methods of this protocol to make API calls.")
    println("\(options.visibility.sourceSnippet) protocol \(clientProtocolName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions?) -> UnaryCall<\(methodInputName), \(methodOutputName)>")

      case .serverStreaming:
        println("func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions?, handler: @escaping (\(methodOutputName)) -> Void) -> ServerStreamingCall<\(methodInputName), \(methodOutputName)>")

      case .clientStreaming:
        println("func \(methodFunctionName)(callOptions: CallOptions?) -> ClientStreamingCall<\(methodInputName), \(methodOutputName)>")

      case .bidirectionalStreaming:
        println("func \(methodFunctionName)(callOptions: CallOptions?, handler: @escaping (\(methodOutputName)) -> Void) -> BidirectionalStreamingCall<\(methodInputName), \(methodOutputName)>")
      }
    }
    outdent()
    println("}")
  }

  private func printServiceClientImplementation() {
    println("\(access) final class \(clientClassName): GRPCClient, \(clientProtocolName) {")
    indent()
    println("\(access) let channel: GRPCChannel")
    println("\(access) var defaultCallOptions: CallOptions")
    println()
    println("/// Creates a client for the \(servicePath) service.")
    println("///")
    printParameters()
    println("///   - channel: `GRPCChannel` to the service host.")
    println("///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.")
    println("\(access) init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {")
    indent()
    println("self.channel = channel")
    println("self.defaultCallOptions = defaultCallOptions")
    outdent()
    println("}")
    println()

    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("/// Asynchronous unary call to \(method.name).")
        println("///")
        printParameters()
        printRequestParameter()
        printCallOptionsParameter()
        println("/// - Returns: A `UnaryCall` with futures for the metadata, status and response.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> UnaryCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return self.makeUnaryCall(path: \"/\(servicePath)/\(method.name)\",")
        println("                          request: request,")
        println("                          callOptions: callOptions ?? self.defaultCallOptions)")
        outdent()
        println("}")

      case .serverStreaming:
        println("/// Asynchronous server-streaming call to \(method.name).")
        println("///")
        printParameters()
        printRequestParameter()
        printCallOptionsParameter()
        printHandlerParameter()
        println("/// - Returns: A `ServerStreamingCall` with futures for the metadata and status.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions? = nil, handler: @escaping (\(methodOutputName)) -> Void) -> ServerStreamingCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return self.makeServerStreamingCall(path: \"/\(servicePath)/\(method.name)\",")
        println("                                    request: request,")
        println("                                    callOptions: callOptions ?? self.defaultCallOptions,")
        println("                                    handler: handler)")
        outdent()
        println("}")

      case .clientStreaming:
        println("/// Asynchronous client-streaming call to \(method.name).")
        println("///")
        printClientStreamingDetails()
        println("///")
        printParameters()
        printCallOptionsParameter()
        println("/// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.")
        println("\(access) func \(methodFunctionName)(callOptions: CallOptions? = nil) -> ClientStreamingCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return self.makeClientStreamingCall(path: \"/\(servicePath)/\(method.name)\",")
        println("                                    callOptions: callOptions ?? self.defaultCallOptions)")
        outdent()
        println("}")

      case .bidirectionalStreaming:
        println("/// Asynchronous bidirectional-streaming call to \(method.name).")
        println("///")
        printClientStreamingDetails()
        println("///")
        printParameters()
        printCallOptionsParameter()
        printHandlerParameter()
        println("/// - Returns: A `ClientStreamingCall` with futures for the metadata and status.")
        println("\(access) func \(methodFunctionName)(callOptions: CallOptions? = nil, handler: @escaping (\(methodOutputName)) -> Void) -> BidirectionalStreamingCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return self.makeBidirectionalStreamingCall(path: \"/\(servicePath)/\(method.name)\",")
        println("                                           callOptions: callOptions ?? self.defaultCallOptions,")
        println("                                           handler: handler)")
        outdent()
        println("}")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printClientStreamingDetails() {
    println("/// Callers should use the `send` method on the returned object to send messages")
    println("/// to the server. The caller should send an `.end` after the final message has been sent.")
  }

  private func printParameters() {
    println("/// - Parameters:")
  }

  private func printRequestParameter() {
    println("///   - request: Request to send to \(method.name).")
  }

  private func printCallOptionsParameter() {
    println("///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.")
  }

  private func printHandlerParameter() {
    println("///   - handler: A closure called when each response is received from the server.")
  }
}
