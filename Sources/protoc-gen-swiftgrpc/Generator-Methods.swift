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
  func printStreamReceiveMethods(receivedType: String) {
    println("/// Do not call this directly, call `receive()` in the protocol extension below instead.")
    println("func receiveInternal(timeout: DispatchTime) throws -> \(receivedType)?")
    println("/// Call this to wait for a result. Nonblocking.")
    println("func receive(completion: @escaping (ResultOrRPCError<\(receivedType)?>) -> Void) throws")
  }
  
  func printStreamReceiveExtension(extendedType: String, receivedType: String) {
    println("\(access) extension \(extendedType) {")
    indent()
    println("/// Call this to wait for a result. Blocking.")
    println("func receive(timeout: DispatchTime = .distantFuture) throws -> \(receivedType)? { return try self.receiveInternal(timeout: timeout) }")
    outdent()
    println("}")
  }
  
  func printStreamSendMethods(sentType: String) {
    println("/// Send a message to the stream. Nonblocking.")
    println("func send(_ message: \(sentType), completion: @escaping (Error?) -> Void) throws")
    println("/// Do not call this directly, call `send()` in the protocol extension below instead.")
    println("func sendInternal(_ message: \(sentType), timeout: DispatchTime) throws")
  }
  
  func printStreamSendExtension(extendedType: String,sentType: String) {
    println("\(access) extension \(extendedType) {")
    indent()
    println("/// Send a message to the stream and wait for the send operation to finish. Blocking.")
    println("func send(_ message: \(sentType), timeout: DispatchTime = .distantFuture) throws { try self.sendInternal(message, timeout: timeout) }")
    outdent()
    println("}")
  }
}
