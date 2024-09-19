/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

#if compiler(>=6.0)
import GRPCCodeGen
import GRPCProtobufCodeGen
#endif

@main
final class GenerateGRPC: CodeGenerator {
  var version: String? {
    Version.versionString
  }

  var projectURL: String {
    "https://github.com/grpc/grpc-swift"
  }

  var supportedFeatures: [Google_Protobuf_Compiler_CodeGeneratorResponse.Feature] {
    [.proto3Optional, .supportsEditions]
  }

  var supportedEditionRange: ClosedRange<Google_Protobuf_Edition> {
    Google_Protobuf_Edition.proto2 ... Google_Protobuf_Edition.edition2023
  }

  // A count of generated files by desired name (actual name may differ to avoid collisions).
  private var generatedFileNames: [String: Int] = [:]

  func generate(
    files fileDescriptors: [FileDescriptor],
    parameter: any CodeGeneratorParameter,
    protoCompilerContext: any ProtoCompilerContext,
    generatorOutputs outputs: any GeneratorOutputs
  ) throws {
    let options = try GeneratorOptions(parameter: parameter)

    for descriptor in fileDescriptors {
      if options.generateReflectionData {
        try self.generateReflectionData(
          descriptor,
          options: options,
          outputs: outputs
        )
      }

      if descriptor.services.isEmpty {
        continue
      }

      if options.generateClient || options.generateServer || options.generateTestClient {
        #if compiler(>=6.0)
        if options.v2 {
          try self.generateV2Stubs(descriptor, options: options, outputs: outputs)
        } else {
          try self.generateV1Stubs(descriptor, options: options, outputs: outputs)
        }
        #else
        try self.generateV1Stubs(descriptor, options: options, outputs: outputs)
        #endif
      }
    }
  }

  private func generateReflectionData(
    _ descriptor: FileDescriptor,
    options: GeneratorOptions,
    outputs: any GeneratorOutputs
  ) throws {
    let fileName = self.uniqueOutputFileName(
      fileDescriptor: descriptor,
      fileNamingOption: options.fileNaming,
      extension: "reflection"
    )

    var options = ExtractProtoOptions()
    options.includeSourceCodeInfo = true
    let proto = descriptor.extractProto(options: options)
    let serializedProto = try proto.serializedData()
    let reflectionData = serializedProto.base64EncodedString()
    try outputs.add(fileName: fileName, contents: reflectionData)
  }

  private func generateV1Stubs(
    _ descriptor: FileDescriptor,
    options: GeneratorOptions,
    outputs: any GeneratorOutputs
  ) throws {
    let fileName = self.uniqueOutputFileName(
      fileDescriptor: descriptor,
      fileNamingOption: options.fileNaming
    )

    let fileGenerator = Generator(descriptor, options: options)
    try outputs.add(fileName: fileName, contents: fileGenerator.code)
  }

  #if compiler(>=6.0)
  private func generateV2Stubs(
    _ descriptor: FileDescriptor,
    options: GeneratorOptions,
    outputs: any GeneratorOutputs
  ) throws {
    let fileName = self.uniqueOutputFileName(
      fileDescriptor: descriptor,
      fileNamingOption: options.fileNaming
    )

    let config = SourceGenerator.Config(options: options)
    let fileGenerator = ProtobufCodeGenerator(configuration: config)
    let contents = try fileGenerator.generateCode(
      from: descriptor,
      protoFileModuleMappings: options.protoToModuleMappings,
      extraModuleImports: options.extraModuleImports
    )

    try outputs.add(fileName: fileName, contents: contents)
  }
  #endif
}

extension GenerateGRPC {
  private func uniqueOutputFileName(
    fileDescriptor: FileDescriptor,
    fileNamingOption: FileNaming,
    component: String = "grpc",
    extension: String = "swift"
  ) -> String {
    let defaultName = outputFileName(
      component: component,
      fileDescriptor: fileDescriptor,
      fileNamingOption: fileNamingOption,
      extension: `extension`
    )
    if let count = self.generatedFileNames[defaultName] {
      self.generatedFileNames[defaultName] = count + 1
      return outputFileName(
        component: "\(count)." + component,
        fileDescriptor: fileDescriptor,
        fileNamingOption: fileNamingOption,
        extension: `extension`
      )
    } else {
      self.generatedFileNames[defaultName] = 1
      return defaultName
    }
  }

  private func outputFileName(
    component: String,
    fileDescriptor: FileDescriptor,
    fileNamingOption: FileNaming,
    extension: String
  ) -> String {
    let ext = "." + component + "." + `extension`
    let pathParts = splitPath(pathname: fileDescriptor.name)
    switch fileNamingOption {
    case .fullPath:
      return pathParts.dir + pathParts.base + ext
    case .pathToUnderscores:
      let dirWithUnderscores =
        pathParts.dir.replacingOccurrences(of: "/", with: "_")
      return dirWithUnderscores + pathParts.base + ext
    case .dropPath:
      return pathParts.base + ext
    }
  }
}

// from apple/swift-protobuf/Sources/protoc-gen-swift/StringUtils.swift
private func splitPath(pathname: String) -> (dir: String, base: String, suffix: String) {
  var dir = ""
  var base = ""
  var suffix = ""

  for character in pathname {
    if character == "/" {
      dir += base + suffix + String(character)
      base = ""
      suffix = ""
    } else if character == "." {
      base += suffix
      suffix = String(character)
    } else {
      suffix += String(character)
    }
  }

  let validSuffix = suffix.isEmpty || suffix.first == "."
  if !validSuffix {
    base += suffix
    suffix = ""
  }
  return (dir: dir, base: base, suffix: suffix)
}

#if compiler(>=6.0)
extension SourceGenerator.Config {
  init(options: GeneratorOptions) {
    let accessLevel: SourceGenerator.Config.AccessLevel
    switch options.visibility {
    case .internal:
      accessLevel = .internal
    case .package:
      accessLevel = .package
    case .public:
      accessLevel = .public
    }

    self.init(
      accessLevel: accessLevel,
      accessLevelOnImports: options.useAccessLevelOnImports,
      client: options.generateClient,
      server: options.generateServer
    )
  }
}
#endif
