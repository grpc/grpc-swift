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
        var clientFileName : String
        if clientCount == 0 {
          clientFileName = package + ".client.pb.swift"
        } else {
          clientFileName = package + "\(clientCount).client.pb.swift"
        }
        
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

        let serverFileName = package + ".server.pb.swift"
        if !generatedFileNames.contains(serverFileName) {
          generatedFileNames.insert(serverFileName)
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
