/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
  internal func printServerMetadata() {
    self.printMetadata(server: true)
  }

  internal func printClientMetadata() {
    self.printMetadata(server: false)
  }

  private func printMetadata(server: Bool) {
    let enumName = server ? self.serviceServerMetadata : self.serviceClientMetadata

    self.withIndentation("\(self.access) enum \(enumName)", braces: .curly) {
      self.println("\(self.access) static let serviceDescriptor = GRPCServiceDescriptor(")
      self.withIndentation {
        self.println("name: \(quoted(self.service.name)),")
        self.println("fullName: \(quoted(self.servicePath)),")
        self.println("methods: [")
        for method in self.service.methods {
          self.method = method
          self.withIndentation {
            self.println("\(enumName).Methods.\(self.methodFunctionName),")
          }
        }
        self.println("]")
      }
      self.println(")")
      self.println()

      self.withIndentation("\(self.access) enum Methods", braces: .curly) {
        for (offset, method) in self.service.methods.enumerated() {
          self.method = method
          self.println(
            "\(self.access) static let \(self.methodFunctionName) = GRPCMethodDescriptor("
          )
          self.withIndentation {
            self.println("name: \(quoted(self.method.name)),")
            self.println("path: \(quoted(self.methodPath)),")
            self.println("type: \(streamingType(self.method).asGRPCCallTypeCase)")
          }
          self.println(")")

          if (offset + 1) < self.service.methods.count {
            self.println()
          }
        }
      }
    }
  }
}

extension Generator {
  internal var serviceServerMetadata: String {
    return nameForPackageService(self.file, self.service) + "ServerMetadata"
  }

  internal var serviceClientMetadata: String {
    return nameForPackageService(self.file, self.service) + "ClientMetadata"
  }

  internal var methodPathUsingClientMetadata: String {
    return "\(self.serviceClientMetadata).Methods.\(self.methodFunctionName).path"
  }
}
