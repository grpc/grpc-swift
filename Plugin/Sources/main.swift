// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Stencil
import Foundation
import SwiftProtobuf
import PluginLibrary

func main() throws {

    let fileSystemLoader = Stencil.FileSystemLoader(paths: ["templates/"])
    let templateEnvironment = Environment(loader: fileSystemLoader)
	
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse()

  var log = ""

  let rawRequest = try Stdin.readall()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(protobuf: rawRequest)

  for protoFile in request.protoFile {
	
	
  	if let package = protoFile.package { 
		  
    log += "File \(protoFile.name!)\n"
    for service in protoFile.service {
      log += "Service \(service.name!)\n"
      for method in service.method {
        log += " Method \(method.name!)\n"
        log += "  input \(method.inputType!)\n"
        log += "  output \(method.outputType!)\n"
        log += "  client_streaming \(method.clientStreaming!)\n"
        log += "  server_streaming \(method.serverStreaming!)\n"
      }
      log += " Options \(service.options)\n"
    }
	
    let context = ["protoFile": protoFile]
    let clientcode = try templateEnvironment.renderTemplate(name: "PACKAGE.client.pb.swift", context: context)
    let servercode = try templateEnvironment.renderTemplate(name: "PACKAGE.server.pb.swift", context: context)

    var clientfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
    clientfile.name = package + ".client.pb.swift"
    clientfile.content = clientcode
    response.file.append(clientfile)

    var serverfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
    serverfile.name = package + ".server.pb.swift"
    serverfile.content = servercode
    response.file.append(serverfile)
    } else {
    	print("ERROR: no package")
    }
  }
  log += "\n\n\n\(request)"

  var logfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
  logfile.name = "swiftgrpc.log"
  logfile.content = log
  response.file.append(logfile)
  
  let serializedResponse = try response.serializeProtobuf()
  Stdout.write(bytes: serializedResponse)
}

try main()
