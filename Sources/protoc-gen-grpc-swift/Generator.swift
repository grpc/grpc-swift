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
import SwiftProtobufPluginLibrary

class Generator {
  internal var options: GeneratorOptions
  private var printer: CodePrinter

  internal var file: FileDescriptor
  internal var service: ServiceDescriptor! // context during generation
  internal var method: MethodDescriptor!   // context during generation

  internal let protobufNamer: SwiftProtobufNamer

  init(_ file: FileDescriptor, options: GeneratorOptions) {
    self.file = file
    self.options = options
    self.printer = CodePrinter()
    self.protobufNamer = SwiftProtobufNamer(
      currentFile: file,
      protoFileToModuleMappings: options.protoToModuleMappings)
    printMain()
  }

  public var code: String {
    return printer.content
  }

  internal func println(_ text: String = "", newline: Bool = true) {
    printer.print(text)
    if newline {
      printer.print("\n")
    }
  }

  internal func indent() {
    printer.indent()
  }

  internal func outdent() {
    printer.outdent()
  }

  internal func withIndentation(body: () -> ()) {
    self.indent()
    body()
    self.outdent()
  }

  private func printMain() {
    printer.print("""
      //
      // DO NOT EDIT.
      //
      // Generated by the protocol buffer compiler.
      // Source: \(file.name)
      //

      //
      // Copyright 2018, gRPC Authors All rights reserved.
      //
      // Licensed under the Apache License, Version 2.0 (the "License");
      // you may not use this file except in compliance with the License.
      // You may obtain a copy of the License at
      //
      //     http://www.apache.org/licenses/LICENSE-2.0
      //
      // Unless required by applicable law or agreed to in writing, software
      // distributed under the License is distributed on an "AS IS" BASIS,
      // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
      // See the License for the specific language governing permissions and
      // limitations under the License.
      //\n
      """)

    let moduleNames = [
        "Foundation",
        "NIO",
        "NIOHTTP1",
        "GRPC",
        "SwiftProtobuf"
    ]

    for moduleName in (moduleNames + options.extraModuleImports).sorted() {
      println("import \(moduleName)")
    }
    // Add imports for required modules
    let moduleMappings = options.protoToModuleMappings
    for importedProtoModuleName in moduleMappings.neededModules(forFile: file) ?? [] {
      println("import \(importedProtoModuleName)")
    }
    println()

    // We defer the check for printing clients to `printClient()` since this could be the 'real'
    // client or the test client.
    for service in file.services {
      self.service = service
      self.printClient()
    }
    println()

    if options.generateServer {
      for service in file.services {
        self.service = service
        printServer()
      }
    }

    if options.generatePayloadConformance {
      self.println()
      self.printProtobufExtensions()
    }
  }
}
