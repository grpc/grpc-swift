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
    printServiceClientProtocol()
    println()
    printServiceClientImplementation()
    if options.generateTestStubs {
      println()
      printServiceClientTestStubs()
    }
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
    if options.generateTestStubs {
      println()
      println("class \(callName)TestStub: ClientCallServerStreamingTestStub<\(methodOutputName)>, \(callName) {")
      indent()
      println("override class var method: String { return \(methodPath) }")
      outdent()
      println("}")
    }
    println()
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
    if options.generateTestStubs {
      println()
      println("/// Simple fake implementation of \(callName)")
      println("/// stores sent values for later verification and finall returns a previously-defined result.")
      println("class \(callName)TestStub: ClientCallClientStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(callName) {")
      indent()
      println("override class var method: String { return \(methodPath) }")
      outdent()
      println("}")
    }
    println()
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
    if options.generateTestStubs {
      println()
      println("class \(callName)TestStub: ClientCallBidirectionalStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(callName) {")
      indent()
      println("override class var method: String { return \(methodPath) }")
      outdent()
      println("}")
    }
    println()
  }

  private func printServiceClientProtocol() {
    println("/// Instantiate \(serviceClassName)Client, then call methods of this protocol to make API calls.")
    println("\(options.visibility.sourceSnippet) protocol \(serviceClassName): ServiceClient {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("/// Synchronous. Unary.")
        println("func \(methodFunctionName)(_ request: \(methodInputName)) throws -> \(methodOutputName)")
        println("/// Asynchronous. Unary.")
        println("func \(methodFunctionName)(_ request: \(methodInputName), completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName)")
      case .serverStreaming:
        println("/// Asynchronous. Server-streaming.")
        println("/// Send the initial message.")
        println("/// Use methods on the returned object to get streamed responses.")
        println("func \(methodFunctionName)(_ request: \(methodInputName), completion: ((CallResult) -> Void)?) throws -> \(callName)")
      case .clientStreaming:
        println("/// Asynchronous. Client-streaming.")
        println("/// Use methods on the returned object to stream messages and")
        println("/// to close the connection and wait for a final response.")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName)")
      case .bidirectionalStreaming:
        println("/// Asynchronous. Bidirectional-streaming.")
        println("/// Use methods on the returned object to stream messages,")
        println("/// to wait for replies, and to close the connection.")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName)")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printServiceClientImplementation() {
    println("\(access) final class \(serviceClassName)Client: ServiceClientBase, \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("/// Synchronous. Unary.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName)) throws -> \(methodOutputName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".run(request: request, metadata: metadata)")
        outdent()
        outdent()
        println("}")
        println("/// Asynchronous. Unary.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(request: request, metadata: metadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      case .serverStreaming:
        println("/// Asynchronous. Server-streaming.")
        println("/// Send the initial message.")
        println("/// Use methods on the returned object to get streamed responses.")
        println("\(access) func \(methodFunctionName)(_ request: \(methodInputName), completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(request: request, metadata: metadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      case .clientStreaming:
        println("/// Asynchronous. Client-streaming.")
        println("/// Use methods on the returned object to stream messages and")
        println("/// to close the connection and wait for a final response.")
        println("\(access) func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(metadata: metadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      case .bidirectionalStreaming:
        println("/// Asynchronous. Bidirectional-streaming.")
        println("/// Use methods on the returned object to stream messages,")
        println("/// to wait for replies, and to close the connection.")
        println("\(access) func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("return try \(callName)Base(channel)")
        indent()
        println(".start(metadata: metadata, completion: completion)")
        outdent()
        outdent()
        println("}")
      }
      println()
    }
    outdent()
    println("}")
  }

  private func printServiceClientTestStubs() {
    println("class \(serviceClassName)TestStub: ServiceClientTestStubBase, \(serviceClassName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("var \(methodFunctionName)Requests: [\(methodInputName)] = []")
        println("var \(methodFunctionName)Responses: [\(methodOutputName)] = []")
        println("func \(methodFunctionName)(_ request: \(methodInputName)) throws -> \(methodOutputName) {")
        indent()
        println("\(methodFunctionName)Requests.append(request)")
        println("defer { \(methodFunctionName)Responses.removeFirst() }")
        println("return \(methodFunctionName)Responses.first!")
        outdent()
        println("}")
        println("func \(methodFunctionName)(_ request: \(methodInputName), completion: @escaping (\(methodOutputName)?, CallResult) -> Void) throws -> \(callName) {")
        indent()
        println("fatalError(\"not implemented\")")
        outdent()
        println("}")
      case .serverStreaming:
        println("var \(methodFunctionName)Requests: [\(methodInputName)] = []")
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(_ request: \(methodInputName), completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("\(methodFunctionName)Requests.append(request)")
        println("defer { \(methodFunctionName)Calls.removeFirst() }")
        println("return \(methodFunctionName)Calls.first!")
        outdent()
        println("}")
      case .clientStreaming:
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
        indent()
        println("defer { \(methodFunctionName)Calls.removeFirst() }")
        println("return \(methodFunctionName)Calls.first!")
        outdent()
        println("}")
      case .bidirectionalStreaming:
        println("var \(methodFunctionName)Calls: [\(callName)] = []")
        println("func \(methodFunctionName)(completion: ((CallResult) -> Void)?) throws -> \(callName) {")
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
}
