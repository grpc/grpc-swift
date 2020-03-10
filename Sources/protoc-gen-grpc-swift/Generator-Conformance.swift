/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import SwiftProtobuf
import SwiftProtobufPluginLibrary

extension Generator {
  internal func printProtobufExtensions() {
    println("// Provides conformance to `GRPCPayload` for request and response messages")
    for service in self.file.services {
      self.service = service
      for method in self.service.methods {
        self.method = method
        self.printExtension(for: self.methodInputName)
        self.printExtension(for: self.methodOutputName)
      }
      println()
    }
  }

  private func printExtension(for messageType: String) {
    guard !self.observedMessages.contains(messageType) else {
      return
    }
    self.println("extension \(messageType): GRPCProtobufPayload {}")
    self.observedMessages.insert(messageType)
  }
}
