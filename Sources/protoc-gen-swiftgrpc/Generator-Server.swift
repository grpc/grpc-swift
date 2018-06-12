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
    println("/// If one of the methods returning `ServerStatus?` returns nil,")
    println("/// it is expected that you have already returned a status to the client by means of `session.close`.")
    println("\(access) protocol \(providerName) {")
    indent()
    for method in service.methods {
      self.method = method
      switch streamingType(method) {
      case .unary:
        println("func \(methodFunctionName)(request: \(methodInputName), session: \(methodSessionName)) throws -> \(methodOutputName)")
      case .serverStreaming:
        println("func \(methodFunctionName)(request: \(methodInputName), session: \(methodSessionName)) throws -> ServerStatus?")
      case .clientStreaming:
        println("func \(methodFunctionName)(session: \(methodSessionName)) throws -> \(methodOutputName)?")
      case .bidirectionalStreaming:
        println("func \(methodFunctionName)(session: \(methodSessionName)) throws -> ServerStatus?")
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
    println("\(access) init?(address: String, certificateURL: URL, keyURL: URL, rootCertsURL: URL? = nil, provider: \(providerName)) {")
    indent()
    println("self.provider = provider")
    println("super.init(address: address, certificateURL: certificateURL, keyURL: keyURL, rootCertsURL: rootCertsURL)")
    outdent()
    println("}")
    println()
    println("\(access) init?(address: String, certificateString: String, keyString: String, rootCerts: String? = nil, provider: \(providerName)) {")
    indent()
    println("self.provider = provider")
    println("super.init(address: address, certificateString: certificateString, keyString: keyString, rootCerts: rootCerts)")
    outdent()
    println("}")
    println()
    println("/// Determines and calls the appropriate request handler, depending on the request's method.")
    println("/// Throws `HandleMethodError.unknownMethod` for methods not handled by this service.")
    println("\(access) override func handleMethod(_ method: String, handler: Handler) throws -> ServerStatus? {")
    indent()
    println("let provider = self.provider")
    println("switch method {")
    for method in service.methods {
      self.method = method
      println("case \(methodPath):")
      indent()
      switch streamingType(method) {
      case .unary, .serverStreaming:
        println("return try \(methodSessionName)Base(")
        indent()
        println("handler: handler,")
        println("providerBlock: { try provider.\(methodFunctionName)(request: $0, session: $1 as! \(methodSessionName)Base) })")
        indent()
        println(".run()")
        outdent()
        outdent()
      default:
        println("return try \(methodSessionName)Base(")
        indent()
        println("handler: handler,")
        println("providerBlock: { try provider.\(methodFunctionName)(session: $0 as! \(methodSessionName)Base) })")
        indent()
        println(".run()")
        outdent()
        outdent()
      }
      outdent()
    }
    println("default:")
    indent()
    println("throw HandleMethodError.unknownMethod")
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
  
  private func printServerMethodSendAndClose(sentType: String) {
    println("/// Exactly one of these two methods should be called if and only if your request handler returns nil;")
    println("/// otherwise SwiftGRPC will take care of sending the response and status for you.")
    println("/// Close the connection and send a single result. Non-blocking.")
    println("func sendAndClose(response: \(sentType), status: ServerStatus, completion: (() -> Void)?) throws")
    println("/// Close the connection and send an error. Non-blocking.")
    println("/// Use this method if you encountered an error that makes it impossible to send a response.")
    println("/// Accordingly, it does not make sense to call this method with a status of `.ok`.")
    println("func sendErrorAndClose(status: ServerStatus, completion: (() -> Void)?) throws")
  }

  private func printServerMethodClientStreaming() {
    println("\(access) protocol \(methodSessionName): ServerSessionClientStreaming {")
    indent()
    printStreamReceiveMethods(receivedType: methodInputName)
    println()
    printServerMethodSendAndClose(sentType: methodOutputName)
    outdent()
    println("}")
    println()
    printStreamReceiveExtension(extendedType: methodSessionName, receivedType: methodInputName)
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionClientStreamingBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionClientStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    }
  }

  private func printServerMethodClose() {
    println("/// Close the connection and send the status. Non-blocking.")
    println("/// This method should be called if and only if your request handler returns a nil value instead of a server status;")
    println("/// otherwise SwiftGRPC will take care of sending the status for you.")
    println("func close(withStatus status: ServerStatus, completion: (() -> Void)?) throws")
  }
  
  private func printServerMethodServerStreaming() {
    println("\(access) protocol \(methodSessionName): ServerSessionServerStreaming {")
    indent()
    printStreamSendMethods(sentType: methodOutputName)
    println()
    printServerMethodClose()
    outdent()
    println("}")
    println()
    printStreamSendExtension(extendedType: methodSessionName, sentType: methodOutputName)
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
    printStreamReceiveMethods(receivedType: methodInputName)
    println()
    printStreamSendMethods(sentType: methodOutputName)
    println()
    printServerMethodClose()
    outdent()
    println("}")
    println()
    printStreamReceiveExtension(extendedType: methodSessionName, receivedType: methodInputName)
    println()
    printStreamSendExtension(extendedType: methodSessionName, sentType: methodOutputName)
    println()
    println("fileprivate final class \(methodSessionName)Base: ServerSessionBidirectionalStreamingBase<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    if options.generateTestStubs {
      println()
      println("class \(methodSessionName)TestStub: ServerSessionBidirectionalStreamingTestStub<\(methodInputName), \(methodOutputName)>, \(methodSessionName) {}")
    }
  }
}
