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
    printClientProtocolExtension()
    println()
    printServiceClientImplementation()
  }

  private func printFunction(name: String, arguments: [String], returnType: String, access: String? = nil, bodyBuilder: (() -> ())?) {
    // Add a space after access, if it exists.
    let accessOrEmpty = access.map { $0 + " " } ?? ""

    let hasBody = bodyBuilder != nil

    if arguments.isEmpty {
      // Don't bother splitting across multiple lines if there are no arguments.
      self.println("\(accessOrEmpty)func \(name)() -> \(returnType)", newline: !hasBody)
    } else {
      self.println("\(accessOrEmpty)func \(name)(")
      self.withIndentation {
        // Add a comma after each argument except the last.
        arguments.forEach(beforeLast: {
          self.println($0 + ",")
        }, onLast: {
          self.println($0)
        })
      }
      self.println(") -> \(returnType)", newline: !hasBody)
    }

    if let bodyBuilder = bodyBuilder {
      self.println(" {")
      self.withIndentation {
        bodyBuilder()
      }
      self.println("}")
    }
  }

  private func printServiceClientProtocol() {
    self.println("/// Usage: instantiate \(self.clientClassName), then call methods of this protocol to make API calls.")
    self.println("\(self.access) protocol \(self.clientProtocolName): GRPCClient {")
    self.withIndentation {
      for method in service.methods {
        self.method = method

        self.printFunction(
          name: self.methodFunctionName,
          arguments: self.methodArguments,
          returnType: self.methodReturnType,
          bodyBuilder: nil
        )

        self.println()
      }
    }
    println("}")
  }

  private func printClientProtocolExtension() {
    self.println("extension \(self.clientProtocolName) {")
    self.withIndentation {
      for method in service.methods {
        self.method = method
        let body: () -> ()

        switch streamingType(method) {
        case .unary:
          body = {
            self.println("return self.\(self.methodFunctionName)(request, callOptions: self.defaultCallOptions)")
          }

        case .serverStreaming:
          body = {
            self.println("return self.\(self.methodFunctionName)(request, callOptions: self.defaultCallOptions, handler: handler)")
          }

        case .clientStreaming:
          body = {
            self.println("return self.\(self.methodFunctionName)(callOptions: self.defaultCallOptions)")
          }

        case .bidirectionalStreaming:
          body = {
            self.println("return self.\(self.methodFunctionName)(callOptions: self.defaultCallOptions, handler: handler)")
          }
        }

        self.printFunction(
          name: self.methodFunctionName,
          arguments: self.methodArgumentsWithoutCallOptions,
          returnType: self.methodReturnType,
          access: self.access,
          bodyBuilder: body
        )
        self.println()
      }
    }
    self.println("}")
  }

  private func printServiceClientImplementation() {
    println("\(access) final class \(clientClassName): \(clientProtocolName) {")
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
    self.printFunction(
      name: self.methodFunctionName,
      arguments: self.methodArguments,
      returnType: self.methodReturnType,
      access: self.access
    ) {
      self.println("return \(callFactory).makeUnaryCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions")
      }
      self.println(")")
    }
  }

  private func printServerStreamingCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printParameters()
    self.printRequestParameter()
    self.printCallOptionsParameter()
    self.printHandlerParameter()
    self.println("/// - Returns: A `ServerStreamingCall` with futures for the metadata and status.")
    self.printFunction(
      name: self.methodFunctionName,
      arguments: self.methodArguments,
      returnType: self.methodReturnType,
      access: self.access
    ) {
      self.println("return \(callFactory).makeServerStreamingCall(") // path: \"/\(servicePath)/\(method.name)\",")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions,")
        self.println("handler: handler")
      }
      self.println(")")
    }
  }

  private func printClientStreamingCall(callFactory: String) {
    self.println(self.method.documentation(streamingType: self.streamType), newline: false)
    self.println("///")
    self.printClientStreamingDetails()
    self.println("///")
    self.printParameters()
    self.printCallOptionsParameter()
    self.println("/// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.")
    self.printFunction(
      name: self.methodFunctionName,
      arguments: self.methodArguments,
      returnType: self.methodReturnType,
      access: self.access
    ) {
      self.println("return \(callFactory).makeClientStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions")
      }
      self.println(")")
    }
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
    self.printFunction(
      name: self.methodFunctionName,
      arguments: self.methodArguments,
      returnType: self.methodReturnType,
      access: self.access
    ) {
      self.println("return \(callFactory).makeBidirectionalStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions,")
        self.println("handler: handler")
      }
      self.println(")")
    }
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
    println("///   - callOptions: Call options.")
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

extension Generator {
  fileprivate var methodArguments: [String] {
    switch self.streamType {
    case .unary:
      return [
        "_ request: \(self.methodInputName)",
        "callOptions: CallOptions"
      ]
    case .serverStreaming:
      return [
        "_ request: \(self.methodInputName)",
        "callOptions: CallOptions",
        "handler: @escaping (\(methodOutputName)) -> Void"
      ]

    case .clientStreaming:
      return ["callOptions: CallOptions"]

    case .bidirectionalStreaming:
      return [
        "callOptions: CallOptions",
        "handler: @escaping (\(methodOutputName)) -> Void"
      ]
    }
  }


  fileprivate var methodArgumentsWithoutCallOptions: [String] {
    return self.methodArguments.filter {
      !$0.hasPrefix("callOptions: ")
    }
  }

  fileprivate var methodReturnType: String {
    switch self.streamType {
    case .unary:
      return "UnaryCall<\(self.methodInputName), \(self.methodOutputName)>"

    case .serverStreaming:
      return "ServerStreamingCall<\(self.methodInputName), \(self.methodOutputName)>"

    case .clientStreaming:
      return "ClientStreamingCall<\(self.methodInputName), \(self.methodOutputName)>"

    case .bidirectionalStreaming:
      return "BidirectionalStreamingCall<\(self.methodInputName), \(self.methodOutputName)>"
    }

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

extension Array {
  /// Like `forEach` except that the `body` closure operates on all elements except for the last,
  /// and the `last` closure only operates on the last element.
  fileprivate func forEach(beforeLast body: (Element) -> (), onLast last: (Element) -> ()) {
    for element in self.dropLast() {
      body(element)
    }
    if let lastElement = self.last {
      last(lastElement)
    }
  }
}
