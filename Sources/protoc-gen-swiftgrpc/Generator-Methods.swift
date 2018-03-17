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
    println("/// Call this to wait for a result. Blocking.")
    println("func receive() throws -> \(receivedType)?")
    println("/// Call this to wait for a result. Nonblocking.")
    println("func receive(completion: @escaping (ResultOrRPCError<\(receivedType)?>) -> Void) throws")
  }
  
  func printStreamSendMethods(sentType: String) {
    println("/// Send a message to the stream. Nonblocking.")
    println("func send(_ message: \(sentType), completion: @escaping (Error?) -> Void) throws")
    println("/// Send a message to the stream and wait for the send operation to finish. Blocking.")
    println("func send(_ message: \(sentType)) throws")
  }
}
