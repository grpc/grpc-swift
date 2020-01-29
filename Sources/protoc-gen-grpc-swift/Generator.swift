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

  internal func println(_ text: String = "") {
    printer.print(text)
    printer.print("\n")
  }

  internal func indent() {
    printer.indent()
  }

  internal func outdent() {
    printer.outdent()
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
    // Build systems like Bazel will generate the Swift service definitions in a different module
    // than the rest of the protos defined in the same file (because they are generated by separate
    // build rules that invoke the separate generator plugins). So, we need to specify module
    // mappings to import the service protos as well as and any other proto modules that the file
    // imports.
    let moduleMappings = options.protoToModuleMappings
    if let serviceProtoModuleName = moduleMappings.moduleName(forFile: file) {
      println("import \(serviceProtoModuleName)")
    }
    for importedProtoModuleName in moduleMappings.neededModules(forFile: file) ?? [] {
      println("import \(importedProtoModuleName)")
    }
    println()

    if options.generateClient {
      for service in file.services {
        self.service = service
        printClient()
      }
    }
    println()

    if options.generateServer {
      for service in file.services {
        self.service = service
        printServer()
      }
    }
    println()
    printProtoBufExtensions()
  }
    
  internal func printProtoBufExtensions() {
    var writtenValues = Set<String>()
    for service in file.services {
      self.service = service
      println("/// Provides conformance to `GRPCPayload` for the request and response messages")
      for method in service.methods {
        self.method = method
        printExtension(for: methodInputName, typesSeen: &writtenValues)
        printExtension(for: methodOutputName, typesSeen: &writtenValues)
      }
    }
  }

  private func printExtension(for messageType: String, typesSeen: inout Set<String>) {
    guard !typesSeen.contains(messageType) else { return }
    println("extension \(messageType): GRPCProtobufPayload {}")
    typesSeen.insert(messageType)
  }
}
