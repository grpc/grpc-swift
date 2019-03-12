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
  internal func printClient(asynchronousCode: Bool,
                            synchronousCode: Bool) {
    if options.generateNIOImplementation {
      printNIOGRPCClient()
    } else {
      printCGRPCClient(asynchronousCode: asynchronousCode,
                       synchronousCode: synchronousCode)
      if options.generateTestStubs {
        printCGRPCClientTestStubs(asynchronousCode: asynchronousCode,
                                 synchronousCode: synchronousCode)
      }
    }
  }

  private func printCGRPCClient(asynchronousCode: Bool,
                                synchronousCode: Bool) {
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        printServiceClientMethodCallUnary()
      case .serverStreaming:
        printServiceClientMethodCallServerStreaming()
      case .clientStreaming:
        printServiceClientMethodCallClientStreaming()
      case .bidirectionalStreaming:
        printServiceClientMethodCallBidiStreaming()
      }
    }
    println()
    printServiceClientProtocol(asynchronousCode: asynchronousCode,
                               synchronousCode: synchronousCode)
    println()
    printServiceClientProtocolExtension(asynchronousCode: asynchronousCode,
                                        synchronousCode: synchronousCode)
    println()
    printServiceClientImplementation(asynchronousCode: asynchronousCode,
                                     synchronousCode: synchronousCode)
  }

  private func printCGRPCClientTestStubs(asynchronousCode: Bool,
                                         synchronousCode: Bool) {
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        printServiceClientMethodCallUnaryTestStub()
      case .serverStreaming:
        printServiceClientMethodCallServerStreamingTestStub()
      case .clientStreaming:
        printServiceClientMethodCallClientStreamingTestStub()
      case .bidirectionalStreaming:
        printServiceClientMethodCallBidiStreamingTestStub()
      }
    }
    println()
    printServiceClientTestStubs(asynchronousCode: asynchronousCode, synchronousCode: synchronousCode)
  }

  private func printServiceClientMethodCallUnary() {
    println("\(access) protocol \(callName): ClientCallUnary {}")
    println()
    println("fileprivate final class \(callName)Base: ClientCallUnaryBase<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
    println()
  }

  private func printServiceClientMethodCallUnaryTestStub() {
    println()
    println("class \(callName)TestStub: ClientCallUnaryTestStub, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
  }

  private func printServiceClientMethodCallServerStreaming() {
    println("\(access) protocol \(callName): ClientCallServerStreaming {")
    indent()
    printStreamReceiveMethods(receivedType: methodOutputName)
    outdent()
    println("}")
    println()
    printStreamReceiveExtension(extendedType: callName, receivedType: methodOutputName)
    println()
    println("fileprivate final class \(callName)Base: ClientCallServerStreamingBase<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
    println()
  }

  private func printServiceClientMethodCallServerStreamingTestStub() {
    println()
    println("class \(callName)TestStub: ClientCallServerStreamingTestStub<\(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
  }

  private func printServiceClientMethodCallClientStreaming() {
    println("\(options.visibility.sourceSnippet) protocol \(callName): ClientCallClientStreaming {")
    indent()
    printStreamSendMethods(sentType: methodInputName)
    println()
    println("/// Call this to close the connection and wait for a response. Blocking.")
    println("func closeAndReceive() throws -> \(methodOutputName)")
    println("/// Call this to close the connection and wait for a response. Nonblocking.")
    println("func closeAndReceive(completion: @escaping (ResultOrRPCError<\(methodOutputName)>) -> Void) throws")
    outdent()
    println("}")
    println()
    printStreamSendExtension(extendedType: callName, sentType: methodInputName)
    println()
    println("fileprivate final class \(callName)Base: ClientCallClientStreamingBase<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
    println()
  }

  private func printServiceClientMethodCallClientStreamingTestStub() {
    println()
    println("/// Simple fake implementation of \(callName)")
    println("/// stores sent values for later verification and finall returns a previously-defined result.")
    println("class \(callName)TestStub: ClientCallClientStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
  }

  private func printServiceClientMethodCallBidiStreaming() {
    println("\(access) protocol \(callName): ClientCallBidirectionalStreaming {")
    indent()
    printStreamReceiveMethods(receivedType: methodOutputName)
    println()
    printStreamSendMethods(sentType: methodInputName)
    println()
    println("/// Call this to close the sending connection. Blocking.")
    println("func closeSend() throws")
    println("/// Call this to close the sending connection. Nonblocking.")
    println("func closeSend(completion: (() -> Void)?) throws")
    outdent()
    println("}")
    println()
    printStreamReceiveExtension(extendedType: callName, receivedType: methodOutputName)
    println()
    printStreamSendExtension(extendedType: callName, sentType: methodInputName)
    println()
    println("fileprivate final class \(callName)Base: ClientCallBidirectionalStreamingBase<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
    println()
  }

  private func printServiceClientMethodCallBidiStreamingTestStub() {
    println()
    println("class \(callName)TestStub: ClientCallBidirectionalStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(callName) {")
    indent()
    println("override class var method: String { return \(methodPath) }")
    outdent()
    println("}")
  }

  private func printServiceClientProtocol(asynchronousCode: Bool,
                                          synchronousCode: Bool) {
    println("/// Instantiate \(serviceClassName)Client, then call methods of this protocol to make API calls.")
    println("\(options.visibility.sourceSnippet) protocol \(serviceClassName): ServiceClient {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        if synchronousCode {
          println("/// Synchronous. Unary.")
          println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata) throws -> \(methodOutputName)")
        }
        if asynchronousCode {
          println("/// Asynchronous. Unary.")
          println("@discardableResult")
          println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName)")
        }
      case .serverStreaming:
        println("/// Asynchronous. Server-streaming.")
        println("/// Send the initial message.")
        println("/// Use methods on the returned object to get streamed responses.")
        println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName)")
      case .clientStreaming:
        println("/// Asynchronous. Client-streaming.")
        println("/// Use methods on the returned object to stream messages and")
        println("/// to close the connection and wait for a final response.")
        println("func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName)")
      case .bidirectionalStreaming:
        println("/// Asynchronous. Bidirectional-streaming.")
        println("/// Use methods on the returned object to stream messages,")
        println("/// to wait for replies, and to close the connection.")
        println("func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName)")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printServiceClientProtocolExtension(asynchronousCode: Bool,
                                                   synchronousCode: Bool) {
    println("\(options.visibility.sourceSnippet) extension \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        if synchronousCode {
          println("/// Synchronous. Unary.")
          println("func \(methodFunctionName)(_ request: \(methodInputName)) throws -> \(methodOutputName) {")
          indent()
          println("return try self.\(methodFunctionName)(request, metadata: self.metadata)")
          outdent()
          println("}")
        }
        if asynchronousCode {
          println("/// Asynchronous. Unary.")
          println("@discardableResult")
          println("func \(methodFunctionName)(_ request: \(methodInputName), completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName) {")
          indent()
          println("return try self.\(methodFunctionName)(request, metadata: self.metadata, completion: completion)")
          outdent()
          println("}")
        }
      case .serverStreaming:
        println("/// Asynchronous. Server-streaming.")
        println("func \(methodFunctionName)(_ request: \(methodInputName), completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try self.\(methodFunctionName)(request, metadata: self.metadata, completion: completion)")
        outdent()
        println("}")
      case .clientStreaming:
        println("/// Asynchronous. Client-streaming.")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try self.\(methodFunctionName)(metadata: self.metadata, completion: completion)")
        outdent()
        println("}")
      case .bidirectionalStreaming:
        println("/// Asynchronous. Bidirectional-streaming.")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try self.\(methodFunctionName)(metadata: self.metadata, completion: completion)")
        outdent()
        println("}")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printServiceClientImplementation(asynchronousCode: Bool,
                                                synchronousCode: Bool) {
    println("\(access) final class \(serviceClassName)Client: ServiceClientBase, \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        if synchronousCode {
          println("/// Synchronous. Unary.")
          println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata) throws -> \(methodOutputName) {")
          indent()
          println("return try \(callName)Base(channel)")
          indent()
          println(".run(request: request, metadata: customMetadata)")
          outdent()
          outdent()
          println("}")
        }
        if asynchronousCode {
          println("/// Asynchronous. Unary.")
          println("@discardableResult")
          println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName) {")
          indent()
          println("return try \(callName)Base(channel)")
          indent()
          println(".start(request: request, metadata: customMetadata, completion: completion)")
          outdent()
          outdent()
          println("}")
        }
      case .serverStreaming:
        println("/// Asynchronous. Server-streaming.")
        println("/// Send the initial message.")
        println("/// Use methods on the returned object to get streamed responses.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(request: request, metadata: customMetadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      case .clientStreaming:
        println("/// Asynchronous. Client-streaming.")
        println("/// Use methods on the returned object to stream messages and")
        println("/// to close the connection and wait for a final response.")
        println("\(access) func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(metadata: customMetadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      case .bidirectionalStreaming:
        println("/// Asynchronous. Bidirectional-streaming.")
        println("/// Use methods on the returned object to stream messages,")
        println("/// to wait for replies, and to close the connection.")
        println("\(access) func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(metadata: customMetadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printServiceClientTestStubs(asynchronousCode: Bool,
                                           synchronousCode: Bool) {
    println("class \(serviceClassName)TestStub: ServiceClientTestStubBase, \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("var \(methodFunctionName)Requests: [\(methodInputName)] = []")
        println("var \(methodFunctionName)Responses: [\(methodOutputName)] = []")
        if synchronousCode {
          println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata) throws -> \(methodOutputName) {")
          indent()
          println("\(methodFunctionName)Requests.append(request)")
          println("defer { \(methodFunctionName)Responses.removeFirst() }")
          println("return \(methodFunctionName)Responses.first!")
          outdent()
          println("}")
        }
        if asynchronousCode {
          println("@discardableResult")
          println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName) {")
          indent()
          println("fatalError(\"not implemented\")")
          outdent()
          println("}")
        }
      case .serverStreaming:
        println("var \(methodFunctionName)Requests: [\(methodInputName)] = []")
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(_ request: \(methodInputName), metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("\(methodFunctionName)Requests.append(request)")
        println("defer { \(methodFunctionName)Calls.removeFirst() }")
        println("return \(methodFunctionName)Calls.first!")
        outdent()
        println("}")
      case .clientStreaming:
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("defer { \(methodFunctionName)Calls.removeFirst() }")
        println("return \(methodFunctionName)Calls.first!")
        outdent()
        println("}")
      case .bidirectionalStreaming:
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(metadata customMetadata: Metadata, completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("defer { \(methodFunctionName)Calls.removeFirst() }")
        println("return \(methodFunctionName)Calls.first!")
        outdent()
        println("}")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printNIOGRPCClient() {
    println()
    printNIOServiceClientProtocol()
    println()
    printNIOServiceClientImplementation()
  }

  private func printNIOServiceClientProtocol() {
    println("/// Usage: instantiate \(serviceClassName)Client, then call methods of this protocol to make API calls.")
    println("\(options.visibility.sourceSnippet) protocol \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions?) -> UnaryClientCall<\(methodInputName), \(methodOutputName)>")

      case .serverStreaming:
        println("func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions?, handler: @escaping (\(methodOutputName)) -> Void) -> ServerStreamingClientCall<\(methodInputName), \(methodOutputName)>")

      case .clientStreaming:
        println("func \(methodFunctionName)(callOptions: CallOptions?) -> ClientStreamingClientCall<\(methodInputName), \(methodOutputName)>")

      case .bidirectionalStreaming:
        println("func \(methodFunctionName)(callOptions: CallOptions?, handler: @escaping (\(methodOutputName)) -> Void) -> BidirectionalStreamingClientCall<\(methodInputName), \(methodOutputName)>")
      }
    }
    outdent()
    println("}")
  }

  private func printNIOServiceClientImplementation() {
    println("\(access) final class \(serviceClassName)Client: GRPCServiceClient, \(serviceClassName) {")
    indent()
    println("\(access) let client: GRPCClient")
    println("\(access) let service = \"\(servicePath)\"")
    println("\(access) var defaultCallOptions: CallOptions")
    println()
    println("/// Creates a client for the \(servicePath) service.")
    println("///")
    printParameters()
    println("///   - client: `GRPCClient` with a connection to the service host.")
    println("///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them. Defaults to `client.defaultCallOptions`.")
    println("\(access) init(client: GRPCClient, defaultCallOptions: CallOptions? = nil) {")
    indent()
    println("self.client = client")
    println("self.defaultCallOptions = defaultCallOptions ?? client.defaultCallOptions")
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
        println("/// - Returns: A `UnaryClientCall` with futures for the metadata, status and response.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> UnaryClientCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return UnaryClientCall(client: client, path: path(forMethod: \"\(method.name)\"), request: request, callOptions: callOptions ?? self.defaultCallOptions)")
        outdent()
        println("}")

      case .serverStreaming:
        println("/// Asynchronous server-streaming call to \(method.name).")
        println("///")
        printParameters()
        printRequestParameter()
        printCallOptionsParameter()
        printHandlerParameter()
        println("/// - Returns: A `ServerStreamingClientCall` with futures for the metadata and status.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), callOptions: CallOptions? = nil, handler: @escaping (\(methodOutputName)) -> Void) -> ServerStreamingClientCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return ServerStreamingClientCall(client: client, path: path(forMethod: \"\(method.name)\"), request: request, callOptions: callOptions ?? self.defaultCallOptions, handler: handler)")
        outdent()
        println("}")

      case .clientStreaming:
        println("/// Asynchronous client-streaming call to \(method.name).")
        println("///")
        printClientStreamingDetails()
        println("///")
        printParameters()
        printCallOptionsParameter()
        println("/// - Returns: A `ClientStreamingClientCall` with futures for the metadata, status and response.")
        println("\(access) func \(methodFunctionName)(callOptions: CallOptions? = nil) -> ClientStreamingClientCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return ClientStreamingClientCall(client: client, path: path(forMethod: \"\(method.name)\"), callOptions: callOptions ?? self.defaultCallOptions)")
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
        println("/// - Returns: A `ClientStreamingClientCall` with futures for the metadata and status.")
        println("\(access) func \(methodFunctionName)(callOptions: CallOptions? = nil, handler: @escaping (\(methodOutputName)) -> Void) -> BidirectionalStreamingClientCall<\(methodInputName), \(methodOutputName)> {")
        indent()
        println("return BidirectionalStreamingClientCall(client: client, path: path(forMethod: \"\(method.name)\"), callOptions: callOptions ?? self.defaultCallOptions, handler: handler)")
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
