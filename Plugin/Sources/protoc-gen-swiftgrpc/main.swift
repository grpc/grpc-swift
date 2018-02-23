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
import PathKit
import Stencil
import SwiftProtobuf
import SwiftProtobufPluginLibrary

func Log(_ message: String) {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// Code templates use "//-" prefixes to comment-out template operators
// to keep them from interfering with Swift code formatting tools.
// Use this to remove them after templates have been expanded.
func stripMarkers(_ code: String) -> String {
  let inputLines = code.components(separatedBy: "\n")

  var outputLines: [String] = []
  for line in inputLines {
    if line.contains("//-") {
      let removed = line.replacingOccurrences(of: "//-", with: "")
      if removed.trimmingCharacters(in: CharacterSet.whitespaces) != "" {
        outputLines.append(removed)
      }
    } else {
      outputLines.append(line)
    }
  }
  return outputLines.joined(separator: "\n")
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

enum OutputNaming: String {
  case FullPath
  case PathToUnderscores
  case DropPath
}

var outputNamingOption: OutputNaming = .FullPath // temporarily hard-coded

func outputFileName(component: String, fileDescriptor: FileDescriptor) -> String {
  let ext = "." + component + ".swift"
  let pathParts = splitPath(pathname: fileDescriptor.name)
  switch outputNamingOption {
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

var generatedFiles: [String: Int] = [:]

func uniqueOutputFileName(component: String, fileDescriptor: FileDescriptor) -> String {
  let defaultName = outputFileName(component: component, fileDescriptor: fileDescriptor)
  if let count = generatedFiles[defaultName] {
    generatedFiles[defaultName] = count + 1
    return outputFileName(component: "\(count)." + component, fileDescriptor: fileDescriptor)
  } else {
    generatedFiles[defaultName] = 1
    return defaultName
  }
}

func main() throws {
  // initialize template engine and add custom filters
  let templateEnvironment = Environment(loader: InternalLoader(),
                                        extensions: [GRPCFilterExtension()])

  // initialize responses
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse()

  // read plugin input
  let rawRequest = try Stdin.readall()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(serializedData: rawRequest)

  let options = try GeneratorOptions(parameter: request.parameter)

  // Build the SwiftProtobufPluginLibrary model of the plugin input
  let descriptorSet = DescriptorSet(protos: request.protoFile)

  // process each .proto file separately
  for fileDescriptor in descriptorSet.files {
    if fileDescriptor.services.count > 0 {
      // a package declaration is required for file containing service(s)
      let package = fileDescriptor.package

      // generate separate implementation files for client and server
      let context: [String: Any] = [
        "file": fileDescriptor,
        "client": true,
        "server": true,
        "access": options.visibility.sourceSnippet
      ]

      do {
        let grpcFileName = uniqueOutputFileName(component: "grpc", fileDescriptor: fileDescriptor)
        let grpcCode = try templateEnvironment.renderTemplate(name: "main.swift", context: context)
        var grpcFile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
        grpcFile.name = grpcFileName
        grpcFile.content = stripMarkers(grpcCode)
        response.file.append(grpcFile)

      } catch (let error) {
        Log("ERROR \(error)")
      }
    }
  }

  // return everything to the caller
  let serializedResponse = try response.serializedData()
  Stdout.write(bytes: serializedResponse)
}

do {
  try main()
} catch (let error) {
  Log("ERROR: \(error)")
}
