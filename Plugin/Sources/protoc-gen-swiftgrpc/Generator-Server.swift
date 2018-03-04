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
    printServerProtocol()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        printServerMethodUnary()
      case .clientStreaming:
        printServerMethodClientStreaming()
      case .serverStreaming:
        printServerMethodServerStreaming()
      case .bidirectionalStreaming:
        printServerMethodBidirectional()
      }
      println()
    }
    println()
    printServerMainClass()
  }

  private func printServerProtocol() {
    println("/// To build a server, implement a class that conforms to this protocol.")
    println("\(access) protocol \(providerName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("func \(methodFunctionName)(request: \(methodInputName), session: \(methodSessionName)) throws -> \(methodOutputName)")
      case .serverStreaming:
        println("func \(methodFunctionName)(request: \(methodInputName), session: \(methodSessionName)) throws")
      case .clientStreaming:
        println("func \(methodFunctionName)(session: \(methodSessionName)) throws")
      case .bidirectionalStreaming:
        println("func \(methodFunctionName)(session: \(methodSessionName)) throws")
      }
    }
    outdent()
    println("}")
    println()
  }

  private func printServerMainClass() {
    println("/// Main server for generated service")
    println("\(access) final class \(serverName): ServiceServer {")
    indent()
    println("private let provider: \(providerName)")
    println()
    println("\(access) init(address: String, provider: \(providerName)) {")
    indent()
    println("self.provider = provider")
    println("super.init(address: address)")
    outdent()
    println("}")
    println()
    println("\(access) init?(address: String, certificateURL: URL, keyURL: URL, provider: \(providerName)) {")
    indent()
    println("self.provider = provider")
    println("super.init(address: address, certificateURL: certificateURL, keyURL: keyURL)")
    outdent()
    println("}")
    println()
    println("/// Start the server.")
    println("\(access) override func handleMethod(_ method: String, handler: Handler, queue: DispatchQueue) throws -> Bool {")
    indent()
    println("let provider = self.provider")
    println("switch method {")
    for method in service.methods {
      self.method = method
      println("case \(methodPath):")
      indent()
      switch streamingType(method) {
      case .unary, .serverStreaming:
        println("try \(methodSessionName)Base(")
        indent()
        println("handler: handler,")
        println("providerBlock: { try provider.\(methodFunctionName)(request: $0, session: $1 as! \(methodSessionName)Base) })")
        indent()
        println(".run(queue: queue)")
        outdent()
        outdent()
      default:
        println("try \(methodSessionName)Base(")
        indent()
        println("handler: handler,")
        println("providerBlock: { try provider.\(methodFunctionName)(session: $0 as! \(methodSessionName)Base) })")
        indent()
        println(".run(queue: queue)")
        outdent()
        outdent()
      }
      println("return true")
      outdent()
    }
    println("default:")
    indent()
    println("return false")
    outdent()
    println("}")
    outdent()
    println("}")
    outdent()
    println("}")
    println()
  }

  private func printServerMethodUnary() {
    println("\(access) protocol \(methodSessionName): ServerSessionUnary {}")
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionUnaryBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionUnaryTestStub, \(methodSessionName) {}")
    }
  }

  private func printServerMethodClientStreaming() {
    println("\(access) protocol \(methodSessionName): ServerSessionClientStreaming {")
    indent()
    println("/// Receive a message. Blocks until a message is received or the client closes the connection.")
    println("func receive() throws -> \(methodInputName)")
    println()
    println("/// Send a response and close the connection.")
    println("func sendAndClose(_ response: \(methodOutputName)) throws")
    outdent()
    println("}")
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionClientStreamingBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionClientStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    }
  }

  private func printServerMethodServerStreaming() {
    println("\(access) protocol \(methodSessionName): ServerSessionServerStreaming {")
    indent()
    println("/// Send a message. Nonblocking.")
    println("func send(_ response: \(methodOutputName), completion: ((Bool) -> Void)?) throws")
    outdent()
    println("}")
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionServerStreamingBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionServerStreamingTestStub<\(methodOutputName)>, \(methodSessionName) {}")
    }
  }

  private func printServerMethodBidirectional() {
    println("\(access) protocol \(methodSessionName): ServerSessionBidirectionalStreaming {")
    indent()
    println("/// Receive a message. Blocks until a message is received or the client closes the connection.")
    println("func receive() throws -> \(methodInputName)")
    println()
    println("/// Send a message. Nonblocking.")
    println("func send(_ response: \(methodOutputName), completion: ((Bool) -> Void)?) throws")
    println()
    println("/// Close a connection. Blocks until the connection is closed.")
    println("func close() throws")
    outdent()
    println("}")
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionBidirectionalStreamingBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionBidirectionalStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    }
  }
}
