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

    if self.options.generateTestClient {
      self.println()
      self.printTestClient()
    }
  }

  private func printFunction(name: String, arguments: [String], returnType: String?, access: String? = nil, bodyBuilder: (() -> ())?) {
    // Add a space after access, if it exists.
    let accessOrEmpty = access.map { $0 + " " } ?? ""
    let `return` = returnType.map { "-> " + $0 } ?? ""

    let hasBody = bodyBuilder != nil

    if arguments.isEmpty {
      // Don't bother splitting across multiple lines if there are no arguments.
      self.println("\(accessOrEmpty)func \(name)() \(`return`)", newline: !hasBody)
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
      self.println(") \(`return`)", newline: !hasBody)
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
          arguments: self.methodArgumentsWithoutDefaults,
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
      self.printMethods()
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
    outdent()
    println("}")
  }

  private func printMethods() {
    for method in self.service.methods {
      self.println()

      self.method = method
      switch self.streamType {
      case .unary:
        self.printUnaryCall()

      case .serverStreaming:
        self.printServerStreamingCall()

      case .clientStreaming:
        self.printClientStreamingCall()

      case .bidirectionalStreaming:
        self.printBidirectionalStreamingCall()
      }
    }
  }

  private func printUnaryCall() {
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
      self.println("return self.makeUnaryCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions ?? self.defaultCallOptions")
      }
      self.println(")")
    }
  }

  private func printServerStreamingCall() {
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
      self.println("return self.makeServerStreamingCall(") // path: \"/\(servicePath)/\(method.name)\",")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("request: request,")
        self.println("callOptions: callOptions ?? self.defaultCallOptions,")
        self.println("handler: handler")
      }
      self.println(")")
    }
  }

  private func printClientStreamingCall() {
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
      self.println("return self.makeClientStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions ?? self.defaultCallOptions")
      }
      self.println(")")
    }
  }

  private func printBidirectionalStreamingCall() {
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
      self.println("return self.makeBidirectionalStreamingCall(")
      self.withIndentation {
        self.println("path: \(self.methodPath),")
        self.println("callOptions: callOptions ?? self.defaultCallOptions,")
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

extension Generator {
  fileprivate func printFakeResponseStreams() {
    for method in self.service.methods {
      self.println()

      self.method = method
      switch self.streamType {
      case .unary, .clientStreaming:
        self.printUnaryResponse()

      case .serverStreaming, .bidirectionalStreaming:
        self.printStreamingResponse()
      }
    }
  }

  fileprivate func printUnaryResponse() {
    self.printResponseStream(isUnary: true)
    self.println()
    self.printEnqueueUnaryResponse(isUnary: true)
    self.println()
    self.printHasResponseStreamEnqueued()
  }

  fileprivate func printStreamingResponse() {
    self.printResponseStream(isUnary: false)
    self.println()
    self.printEnqueueUnaryResponse(isUnary: false)
    self.println()
    self.printHasResponseStreamEnqueued()
  }

  private func printEnqueueUnaryResponse(isUnary: Bool) {
    let name: String
    let responseArg: String
    let responseArgAndType: String
    if isUnary {
      name = "enqueue\(self.method.name)Response"
      responseArg = "response"
      responseArgAndType = "_ \(responseArg): \(self.methodOutputName)"
    } else {
      name = "enqueue\(self.method.name)Responses"
      responseArg = "responses"
      responseArgAndType = "_ \(responseArg): [\(self.methodOutputName)]"
    }

    self.printFunction(
      name: name,
      arguments: [
        responseArgAndType,
        "_ requestHandler: @escaping (FakeRequestPart<\(self.methodInputName)>) -> () = { _ in }"
      ],
      returnType: nil,
      access: self.access
    ) {
      self.println("let stream = self.make\(self.method.name)ResponseStream(requestHandler)")
      if isUnary {
        self.println("// This is the only operation on the stream; try! is fine.")
        self.println("try! stream.sendMessage(\(responseArg))")
      } else {
        self.println("// These are the only operation on the stream; try! is fine.")
        self.println("\(responseArg).forEach { try! stream.sendMessage($0) }")
        self.println("try! stream.sendEnd()")
      }
    }
  }

  private func printResponseStream(isUnary: Bool) {
    let type = isUnary ? "FakeUnaryResponse" : "FakeStreamingResponse"
    let factory = isUnary ? "makeFakeUnaryResponse" : "makeFakeStreamingResponse"

    self.println("/// Make a \(isUnary ? "unary" : "streaming") response for the \(self.method.name) RPC. This must be called")
    self.println("/// before calling '\(self.methodFunctionName)'. See also '\(type)'.")
    self.println("///")
    self.println("/// - Parameter requestHandler: a handler for request parts sent by the RPC.")
    self.printFunction(
      name: "make\(self.method.name)ResponseStream",
      arguments: ["_ requestHandler: @escaping (FakeRequestPart<\(self.methodInputName)>) -> () = { _ in }"],
      returnType: "\(type)<\(self.methodInputName), \(self.methodOutputName)>",
      access: self.access
    ) {
      self.println("return self.fakeChannel.\(factory)(path: \(self.methodPath), requestHandler: requestHandler)")
    }
  }

  private func printHasResponseStreamEnqueued() {
    self.println("/// Returns true if there are response streams enqueued for '\(self.method.name)'")
    self.println("\(self.access) var has\(self.method.name)ResponsesRemaining: Bool {")
    self.withIndentation {
      self.println("return self.fakeChannel.hasFakeResponseEnqueued(forPath: \(self.methodPath))")
    }
    self.println("}")
  }

  fileprivate func printTestClient() {
    self.println("\(self.access) final class \(self.testClientClassName): \(self.clientProtocolName) {")
    self.withIndentation {
      self.println("private let fakeChannel: FakeChannel")
      self.println("\(self.access) var defaultCallOptions: CallOptions")

      self.println()
      self.println("\(self.access) var channel: GRPCChannel {")
      self.withIndentation {
        self.println("return self.fakeChannel")
      }
      self.println("}")
      self.println()

      self.println("\(self.access) init(")
      self.withIndentation {
        self.println("fakeChannel: FakeChannel = FakeChannel(),")
        self.println("defaultCallOptions callOptions: CallOptions = CallOptions()")
      }
      self.println(") {")
      self.withIndentation {
        self.println("self.fakeChannel = fakeChannel")
        self.println("self.defaultCallOptions = callOptions")
      }
      self.println("}")

      self.printFakeResponseStreams()
    }

    self.println("}")  // end class
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
        "callOptions: CallOptions? = nil"
      ]
    case .serverStreaming:
      return [
        "_ request: \(self.methodInputName)",
        "callOptions: CallOptions? = nil",
        "handler: @escaping (\(methodOutputName)) -> Void"
      ]

    case .clientStreaming:
      return ["callOptions: CallOptions? = nil"]

    case .bidirectionalStreaming:
      return [
        "callOptions: CallOptions? = nil",
        "handler: @escaping (\(methodOutputName)) -> Void"
      ]
    }
  }

  fileprivate var methodArgumentsWithoutDefaults: [String] {
    return self.methodArguments.map { arg in
      // Remove default arg from call options.
      if arg == "callOptions: CallOptions? = nil" {
        return "callOptions: CallOptions?"
      } else {
        return arg
      }
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
