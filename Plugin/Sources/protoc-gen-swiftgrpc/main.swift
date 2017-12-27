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
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import Stencil
import PathKit

func Log(_ message : String) {
  FileHandle.standardError.write((message + "\n").data(using:.utf8)!)
}

// Code templates use "//-" prefixes to comment-out template operators
// to keep them from interfering with Swift code formatting tools.
// Use this to remove them after templates have been expanded.
func stripMarkers(_ code:String) -> String {
  let inputLines = code.components(separatedBy:"\n")

  var outputLines : [String] = []
  for line in inputLines {
    if line.contains("//-") {
      let removed = line.replacingOccurrences(of:"//-", with:"")
      if (removed.trimmingCharacters(in:CharacterSet.whitespaces) != "") {
        outputLines.append(removed)
      }
    } else {
      outputLines.append(line)
    }
  }
  return outputLines.joined(separator:"\n")
}

// from apple/swift-protobuf/Sources/protoc-gen-swift/StringUtils.swift
func splitPath(pathname: String) -> (dir:String, base:String, suffix:String) {
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

enum OutputNaming : String {
  case FullPath
  case PathToUnderscores
  case DropPath
}

func outputFileName(component: String, index: Int, fileDescriptor: FileDescriptor) -> String {
  var ext : String
  if index == 0 {
    ext = "." + component + ".pb.swift"
  } else {
    ext = "\(index)." + component + ".pb.swift"
  }
  let pathParts = splitPath(pathname: fileDescriptor.name)
  let outputNamingOption = OutputNaming.FullPath // temporarily hard-coded
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

func main() throws {

  // initialize template engine and add custom filters
  let templateEnvironment = Environment(loader: InternalLoader(),
                                        extensions:[GRPCFilterExtension()])

  // initialize responses
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse()
  var log = ""

  // read plugin input
  let rawRequest = try Stdin.readall()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(serializedData: rawRequest)
  
  let options = try GeneratorOptions(parameter: request.parameter)

  // Build the SwiftProtobufPluginLibrary model of the plugin input
  let descriptorSet = DescriptorSet(protos: request.protoFile)

  var generatedFileNames = Set<String>()
  var clientCount = 0
  var serverCount = 0

  // process each .proto file separately
  for fileDescriptor in descriptorSet.files {

    // log info about the service
    log += "File \(fileDescriptor.name)\n"
    for serviceDescriptor in fileDescriptor.services {
      log += "Service \(serviceDescriptor.name)\n"
      for methodDescriptor in serviceDescriptor.methods {
        log += " Method \(methodDescriptor.name)\n"
        log += "  input \(methodDescriptor.inputType.name)\n"
        log += "  output \(methodDescriptor.outputType.name)\n"
        log += "  client_streaming \(methodDescriptor.proto.clientStreaming)\n"
        log += "  server_streaming \(methodDescriptor.proto.serverStreaming)\n"
      }
    }

    if fileDescriptor.services.count > 0 {
      // a package declaration is required for file containing service(s)
      let package = fileDescriptor.package
      guard package != ""  else {
        print("ERROR: no package for \(fileDescriptor.name)")
        continue
      }
      
      // generate separate implementation files for client and server
      let context : [String:Any] = [
        "file": fileDescriptor,
        "access": options.visibility.sourceSnippet]

      do {
        let clientFileName = outputFileName(component:"client", index:clientCount, fileDescriptor:fileDescriptor)
        if !generatedFileNames.contains(clientFileName) {
          generatedFileNames.insert(clientFileName)
          clientCount += 1
          let clientcode = try templateEnvironment.renderTemplate(name:"client.pb.swift",
                                                                  context: context)
          var clientfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
          clientfile.name = clientFileName
          clientfile.content = stripMarkers(clientcode)
          response.file.append(clientfile)
        }

        let serverFileName = outputFileName(component:"server", index:serverCount, fileDescriptor:fileDescriptor)
        if !generatedFileNames.contains(serverFileName) {
          generatedFileNames.insert(serverFileName)
          serverCount += 1
          let servercode = try templateEnvironment.renderTemplate(name:"server.pb.swift",
                                                                  context: context)
          var serverfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
          serverfile.name = serverFileName
          serverfile.content = stripMarkers(servercode)
          response.file.append(serverfile)
        }
      } catch (let error) {
        Log("ERROR \(error)")
        log += "ERROR: \(error)\n"
      }
    }
  }

  log += "\(request)"

  // add the logfile to the code generation response
  var logfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
  logfile.name = "swiftgrpc.log"
  logfile.content = log
  response.file.append(logfile)

  // return everything to the caller
  let serializedResponse = try response.serializedData()
  Stdout.write(bytes: serializedResponse)
}

do {
  try main()
} catch (let error) {
  Log("ERROR: \(error)")	
}
