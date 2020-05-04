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

    if self.options.testClient {
      self.println()
      self.printTestClient()
    }
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
      let streamType = streamingType(self.method)
      switch streamType {
      case .unary:
        println(self.method.documentation(streamingType: streamType), newline: false)
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
        println(self.method.documentation(streamingType: streamType), newline: false)
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
        println(self.method.documentation(streamingType: streamType), newline: false)
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
        println(self.method.documentation(streamingType: streamType), newline: false)
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

extension Generator {
  fileprivate func printTestClientResponseArrays() {
    for method in self.service.methods {
      self.method = method
      self.println("private var \(self.testResponseArray): [\(self.testResponseType)] = []")
    }
  }

  fileprivate func printTestClientResponseGetter() {
    for method in self.service.methods {
      self.method = method

      self.println()
      self.println("private func next\(self.methodNameWithUppercasedFirstCharacter)Response() -> \(self.testResponseType) {")
      self.withIndentation {
        self.println("if self.\(self.testResponseArray).isEmpty {")
        self.withIndentation {
          self.println("return .makeFailed()")
        }
        self.println("} else {")
        self.withIndentation {
          self.println("return self.\(self.testResponseArray).removeFirst()")
        }
        self.println("}")
      }
      self.println("}")
    }
  }

  fileprivate func printTestClientResponseFactories() {
    for method in self.service.methods {
      self.method = method

      // Uppercase the first character.
      let name = self.method.name.prefix(1).uppercased() + self.method.name.dropFirst()

      self.println()
      self.println("\(self.access) func make\(name)TestResponse(on eventLoop: EventLoop) -> \(self.testResponseType) {")
      self.withIndentation {
        self.println("let response = \(self.testResponseType)(eventLoop: eventLoop)")
        self.println("self.\(self.testResponseArray).append(response)")
        self.println("return response")
      }
      self.println("}")
    }
  }

  fileprivate func printTestClientRPCs() {
    for method in self.service.methods {
      self.method = method

      // Signature
      self.println()
      self.println("\(self.access) func \(self.methodFunctionName)(")
      switch self.streamType {
      case .unary:
        self.withIndentation {
          self.println("_ request: \(self.methodInputName),")
          self.println("callOptions: CallOptions? = nil")
        }
        self.println(") -> \(self.callType) {")
        self.withIndentation {
          self.println("return \(self.callType)(")
          self.withIndentation {
            self.println("testResponse: self.next\(self.methodNameWithUppercasedFirstCharacter)Response(),")
            self.println("callOptions: callOptions ?? CallOptions()")
          }
          self.println(")")
        }


      case .clientStreaming:
        self.withIndentation {
          self.println("callOptions: CallOptions? = nil")
        }
        self.println(") -> \(self.callType) {")
        self.withIndentation {
          self.println("return \(self.callType)(")
          self.withIndentation {
            self.println("testResponse: self.next\(self.methodNameWithUppercasedFirstCharacter)Response(),")
            self.println("callOptions: callOptions ?? CallOptions()")
          }
          self.println(")")
        }

      case .serverStreaming:
        self.withIndentation {
          self.println("_ request: \(self.methodInputName),")
          self.println("callOptions: CallOptions? = nil,")
          self.println("handler: @escaping (\(self.methodOutputName)) -> Void")
        }
        self.println(") -> \(self.callType) {")
        self.withIndentation {
          self.println("return \(self.callType)(")
          self.withIndentation {
            self.println("testResponse: self.next\(self.methodNameWithUppercasedFirstCharacter)Response(),")
            self.println("callOptions: callOptions ?? CallOptions(),")
            self.println("handler: handler")
          }
          self.println(")")
        }

      case .bidirectionalStreaming:
        self.withIndentation {
          self.println("callOptions: CallOptions? = nil,")
          self.println("handler: @escaping (\(self.methodOutputName)) -> Void")
        }
        self.println(") -> \(self.callType) {")
        self.withIndentation {
          self.println("return \(self.callType)(")
          self.withIndentation {
            self.println("testResponse: self.next\(self.methodNameWithUppercasedFirstCharacter)Response(),")
            self.println("callOptions: callOptions ?? CallOptions(),")
            self.println("handler: handler")
          }
          self.println(")")
        }
      }

      self.println("}")
    }
  }

  fileprivate func printTestClient() {
    self.println("\(self.access) final class \(self.testClientClassName): \(self.clientProtocolName) {")
    self.withIndentation {
      self.printTestClientResponseArrays()
      self.printTestClientResponseGetter()

      self.println("\(self.access) init() {")
      self.println("}")

      self.printTestClientResponseFactories()
      self.printTestClientRPCs()
    }

    self.println("}")  // end class
  }
}

fileprivate extension Generator {
  var streamType: StreamingType {
    return streamingType(self.method)
  }

  var methodNameWithUppercasedFirstCharacter: String {
    return self.method.name.prefix(1).uppercased() + self.method.name.dropFirst()
  }

  var testResponseTypeGeneric: String {
    switch self.streamType {
    case .unary, .clientStreaming:
      return "UnaryTestResponse"
    case .serverStreaming, .bidirectionalStreaming:
      return "StreamingTestResponse"
    }
  }

  var testResponseType: String {
    return "\(self.testResponseTypeGeneric)<\(self.methodOutputName)>"
  }

  var testResponseArray: String {
    return "\(self.methodFunctionName)Responses"
  }

  var callType: String {
    return "\(self.streamType.callType)<\(self.methodInputName), \(self.methodOutputName)>"
  }
}

fileprivate extension StreamingType {
  var callType: String {
    switch self {
    case .unary:
      return "UnaryCall"
    case .clientStreaming:
      return "ClientStreamingCall"
    case .serverStreaming:
      return "ServerStreamingCall"
    case .bidirectionalStreaming:
      return "BidirectionalStreamingCall"
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
