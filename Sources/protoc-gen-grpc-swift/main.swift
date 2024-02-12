/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import GRPCCodeGen
import GRPCProtobufCodeGen
import SwiftProtobuf
import SwiftProtobufPluginLibrary

func Log(_ message: String) {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// from apple/swift-protobuf/Sources/protoc-gen-swift/StringUtils.swift
func splitPath(pathname: String) -> (dir: String, base: String, suffix: String) {
  var dir = ""
  var base = ""
  var suffix = ""
  #if swift(>=3.2)
  let pathnameChars = pathname
  #else
  let pathnameChars = pathname.characters
  #endif
  for c in pathnameChars {
    if c == "/" {
      dir += base + suffix + String(c)
      base = ""
      suffix = ""
    } else if c == "." {
      base += suffix
      suffix = String(c)
    } else {
      suffix += String(c)
    }
  }
  #if swift(>=3.2)
  let validSuffix = suffix.isEmpty || suffix.first == "."
  #else
  let validSuffix = suffix.isEmpty || suffix.characters.first == "."
  #endif
  if !validSuffix {
    base += suffix
    suffix = ""
  }
  return (dir: dir, base: base, suffix: suffix)
}

enum FileNaming: String {
  case FullPath
  case PathToUnderscores
  case DropPath
}

func outputFileName(
  component: String,
  fileDescriptor: FileDescriptor,
  fileNamingOption: FileNaming,
  extension: String
) -> String {
  let ext = "." + component + "." + `extension`
  let pathParts = splitPath(pathname: fileDescriptor.name)
  switch fileNamingOption {
  case .FullPath:
    return pathParts.dir + pathParts.base + ext
  case .PathToUnderscores:
    let dirWithUnderscores =
      pathParts.dir.replacingOccurrences(of: "/", with: "_")
    return dirWithUnderscores + pathParts.base + ext
  case .DropPath:
    return pathParts.base + ext
  }
}

func uniqueOutputFileName(
  component: String,
  fileDescriptor: FileDescriptor,
  fileNamingOption: FileNaming,
  generatedFiles: inout [String: Int],
  extension: String = "swift"
) -> String {
  let defaultName = outputFileName(
    component: component,
    fileDescriptor: fileDescriptor,
    fileNamingOption: fileNamingOption,
    extension: `extension`
  )
  if let count = generatedFiles[defaultName] {
    generatedFiles[defaultName] = count + 1
    return outputFileName(
      component: "\(count)." + component,
      fileDescriptor: fileDescriptor,
      fileNamingOption: fileNamingOption,
      extension: `extension`
    )
  } else {
    generatedFiles[defaultName] = 1
    return defaultName
  }
}

func printVersion(args: [String]) {
  // Stip off the file path
  let program = args.first?.split(separator: "/").last ?? "protoc-gen-grpc-swift"
  print("\(program) \(Version.versionString)")
}

func main(args: [String]) throws {
  if args.dropFirst().contains("--version") {
    printVersion(args: args)
    return
  }

  // initialize responses
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse(
    files: [],
    supportedFeatures: [.proto3Optional]
  )

  // read plugin input
  let rawRequest = FileHandle.standardInput.readDataToEndOfFile()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(serializedData: rawRequest)

  let options = try GeneratorOptions(parameter: request.parameter)

  // Build the SwiftProtobufPluginLibrary model of the plugin input
  let descriptorSet = DescriptorSet(protos: request.protoFile)

  // A count of generated files by desired name (actual name may differ to avoid collisions).
  var generatedFiles: [String: Int] = [:]

  // Only generate output for services.
  for name in request.fileToGenerate {
    if let fileDescriptor = descriptorSet.fileDescriptor(named: name) {
      if options.generateReflectionData {
        var binaryFile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
        let binaryFileName = uniqueOutputFileName(
          component: "grpc",
          fileDescriptor: fileDescriptor,
          fileNamingOption: options.fileNaming,
          generatedFiles: &generatedFiles,
          extension: "reflection"
        )
        let serializedFileDescriptorProto = try fileDescriptor.proto.serializedData()
          .base64EncodedString()
        binaryFile.name = binaryFileName
        binaryFile.content = serializedFileDescriptorProto
        response.file.append(binaryFile)
      }
      if !fileDescriptor.services.isEmpty
        && (options.generateClient || options.generateServer || options.generateTestClient)
      {
        var grpcFile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
        let grpcFileName = uniqueOutputFileName(
          component: "grpc",
          fileDescriptor: fileDescriptor,
          fileNamingOption: options.fileNaming,
          generatedFiles: &generatedFiles
        )
        if options.v2 {
          let grpcGenerator = ProtobufCodeGenerator(
            configuration: SourceGenerator.Configuration(options: options)
          )
          grpcFile.content = try grpcGenerator.generateCode(
            from: fileDescriptor,
            protoFileModuleMappings: options.protoToModuleMappings,
            extraModuleImports: options.extraModuleImports
          )
        } else {
          let grpcGenerator = Generator(fileDescriptor, options: options)
          grpcFile.content = grpcGenerator.code
        }
        grpcFile.name = grpcFileName
        response.file.append(grpcFile)
      }
    }
  }

  // return everything to the caller
  let serializedResponse = try response.serializedData()
  FileHandle.standardOutput.write(serializedResponse)
}

do {
  try main(args: CommandLine.arguments)
} catch {
  Log("ERROR: \(error)")
}

extension SourceGenerator.Configuration {
  init(options: GeneratorOptions) {
    let accessLevel: SourceGenerator.Configuration.AccessLevel
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
      client: options.generateClient,
      server: options.generateServer
    )
  }
}
