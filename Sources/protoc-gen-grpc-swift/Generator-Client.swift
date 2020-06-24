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

    self.printMethods()

    outdent()
    println("}")
  }

  private func printMethods(callFactory: String = "self") {
    for method in self.service.methods {
      self.println()

      self.method = method
      switch self.streamType {
      case .unary:
        self.printUnaryCall(callFactory: callFactory)

      case .serverStreaming:
        self.printServerStreamingCall(callFactory: callFactory)

      case .clientStreaming:
        self.printClientStreamingCall(callFactory: callFactory)

      case .bidirectionalStreaming:
        self.printBidirectionalStreamingCall(callFactory: callFactory)
      }
    }
  }

  private func printUnaryCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printParameters()
    self.printRequestParameter()
    self.printCallOptionsParameter()
    self.println("/// - Returns: A `UnaryCall` with futures for the metadata, status and response.")
    self.println("\(self.access) func \(self.methodFunctionName)(")
    self.withIndentation {
      self.println("_ request: \(self.methodInputName),")
      self.println("callOptions: CallOptions? = nil")
    }
    self.println(") -> UnaryCall<\(self.methodInputName), \(self.methodOutputName)> {")
    self.withIndentation {
      self.println("return \(callFactory).makeUnaryCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions ?? self.defaultCallOptions")
      }
      self.println(")")
    }
    self.println("}")
  }

  private func printServerStreamingCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printParameters()
    self.printRequestParameter()
    self.printCallOptionsParameter()
    self.printHandlerParameter()
    self.println("/// - Returns: A `ServerStreamingCall` with futures for the metadata and status.")
    self.println("\(self.access) func \(self.methodFunctionName)(")
    self.withIndentation {
      self.println("_ request: \(self.methodInputName),")
      self.println("callOptions: CallOptions? = nil,")
      self.println("handler: @escaping (\(methodOutputName)) -> Void")
    }
    self.println(") -> ServerStreamingCall<\(methodInputName), \(methodOutputName)> {")
    self.withIndentation {
      self.println("return \(callFactory).makeServerStreamingCall(") // path: \"/\(servicePath)/\(method.name)\",")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions ?? self.defaultCallOptions,")
        self.println("handler: handler")
      }
      self.println(")")
    }
    self.println("}")
  }

  private func printClientStreamingCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printClientStreamingDetails()
    self.println("///")
    self.printParameters()
    self.printCallOptionsParameter()
    self.println("/// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.")
    self.println("\(self.access) func \(self.methodFunctionName)(")
    self.withIndentation {
      self.println("callOptions: CallOptions? = nil")
    }
    self.println(") -> ClientStreamingCall<\(self.methodInputName), \(self.methodOutputName)> {")
    self.withIndentation {
      self.println("return \(callFactory).makeClientStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions ?? self.defaultCallOptions")
      }
      self.println(")")
    }
    self.println("}")
  }

  private func printBidirectionalStreamingCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printClientStreamingDetails()
    self.println("///")
    self.printParameters()
    self.printCallOptionsParameter()
    self.printHandlerParameter()
    self.println("/// - Returns: A `ClientStreamingCall` with futures for the metadata and status.")
    self.println("\(self.access) func \(self.methodFunctionName)(")
    self.withIndentation {
      self.println("callOptions: CallOptions? = nil,")
      self.println("handler: @escaping (\(self.methodOutputName)) -> Void")
    }
    self.println(") -> BidirectionalStreamingCall<\(self.methodInputName), \(self.methodOutputName)> {")
    self.withIndentation {
      self.println("return \(callFactory).makeBidirectionalStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions ?? self.defaultCallOptions,")
        self.println("handler: handler")
      }
      self.println(")")
    }
    self.println("}")
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

fileprivate extension Generator {
  var streamType: StreamingType {
    return streamingType(self.method)
  }
}

fileprivate extension StreamingType {
  var name: String {
    switch self {
    case .unary:
      return "Unary"
    case .clientStreaming:
      return "Client streaming"
    case .serverStreaming:
      return "Server streaming"
    case .bidirectionalStreaming:
      return "Bidirectional streaming"
    }
  }
}

extension MethodDescriptor {
  var documentation: String? {
    let comments = self.protoSourceComments(commentPrefix: "")
    return comments.isEmpty ? nil : comments
  }

  fileprivate func documentation(streamingType: StreamingType) -> String {
    let sourceComments = self.protoSourceComments()

    if sourceComments.isEmpty {
      return "/// \(streamingType.name) call to \(self.name)\n"  // comments end with "\n" already.
    } else {
      return sourceComments  // already prefixed with "///"
    }
  }
}
