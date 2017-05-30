/*
 *
 * Copyright 2017, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

import Foundation
import SwiftProtobuf
import PluginLibrary
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

  var generatedFileNames = Set<String>()

  // process each .proto file separately
  for protoFile in request.protoFile {

    let file = FileDescriptor(proto:protoFile)

    // a package declaration is required
    let package = file.package
    guard package != "" else {
      print("ERROR: no package for \(file.name)")
      continue
    }

    // log info about the service
    log += "File \(file.name)\n"
    for service in file.service {
      log += "Service \(service.name)\n"
      for method in service.method {
        log += " Method \(method.name)\n"
        log += "  input \(method.inputType)\n"
        log += "  output \(method.outputType)\n"
        log += "  client_streaming \(method.clientStreaming)\n"
        log += "  server_streaming \(method.serverStreaming)\n"
      }
    }

    if file.service.count > 0 {

      // generate separate implementation files for client and server
      let context : [String:Any] = ["file": file, "access": "internal"]

      do {
        let clientFileName = package + ".client.pb.swift"
        if !generatedFileNames.contains(clientFileName) {
          generatedFileNames.insert(clientFileName)
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
