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

func protoMessageName(_ name :String?) -> String {
  guard let name = name else {
    return ""
  }
  let parts = name.components(separatedBy:".")
  if parts.count == 3 {
    return parts[1].capitalized + "_" + parts[2]
  } else {
    return name
  }
}

func pathName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw TemplateSyntaxError("path expects 3 arguments")
  }
  guard let protoFile = arguments[0] as? Google_Protobuf_FileDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_FileDescriptorProto" +
        " argument, received \(arguments[0])")
  }
  guard let service = arguments[1] as? Google_Protobuf_ServiceDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_ServiceDescriptorProto" +
        " argument, received \(arguments[1])")
  }
  guard let method = arguments[2] as? Google_Protobuf_MethodDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_MethodDescriptorProto" +
        " argument, received \(arguments[2])")
  }
  return "/" + protoFile.package! + "." + service.name! + "/" + method.name!
}

func packageServiceMethodName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw TemplateSyntaxError("tag expects 3 arguments")
  }
  guard let protoFile = arguments[0] as? Google_Protobuf_FileDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_FileDescriptorProto" +
        " argument, received \(arguments[0])")
  }
  guard let service = arguments[1] as? Google_Protobuf_ServiceDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_ServiceDescriptorProto" +
        " argument, received \(arguments[1])")
  }
  guard let method = arguments[2] as? Google_Protobuf_MethodDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_MethodDescriptorProto" +
        " argument, received \(arguments[2])")
  }
  return protoFile.package!.capitalized + "_" + service.name! + method.name!
}

func packageServiceName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 2 {
    throw TemplateSyntaxError("tag expects 2 arguments")
  }
  guard let protoFile = arguments[0] as? Google_Protobuf_FileDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_FileDescriptorProto" +
        " argument, received \(arguments[0])")
  }
  guard let service = arguments[1] as? Google_Protobuf_ServiceDescriptorProto
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "Google_Protobuf_ServiceDescriptorProto" +
        " argument, received \(arguments[1])")
  }
  return protoFile.package!.capitalized + "_" + service.name!
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
  let fileSystemLoader = FileSystemLoader(paths: ["templates/"])
  let ext = Extension()
  ext.registerFilter("call") { (value: Any?, arguments: [Any?]) in
    return try packageServiceMethodName(arguments) + "Call"
  }
  ext.registerFilter("session") { (value: Any?, arguments: [Any?]) in
    return try packageServiceMethodName(arguments) + "Session"
  }
  ext.registerFilter("path") { (value: Any?, arguments: [Any?]) in
    return try pathName(arguments)
  }
  ext.registerFilter("provider") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "Provider"
  }
  ext.registerFilter("clienterror") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "ClientError"
  }
  ext.registerFilter("servererror") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "ServerError"
  }
  ext.registerFilter("server") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "Server"
  }
  ext.registerFilter("input") { (value: Any?) in
    if let value = value as? Google_Protobuf_MethodDescriptorProto {
      return protoMessageName(value.inputType)
    }
    throw TemplateSyntaxError("message: invalid argument \(value)")
  }
  ext.registerFilter("output") { (value: Any?) in
    if let value = value as? Google_Protobuf_MethodDescriptorProto {
      return protoMessageName(value.outputType)
    }
    throw TemplateSyntaxError("message: invalid argument \(value)")
  }
  let templateEnvironment = Environment(loader: fileSystemLoader,
                                        extensions:[ext])

  // initialize responses
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse()
  var log = ""

  // read plugin input
  let rawRequest = try Stdin.readall()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(protobuf: rawRequest)

  // process each .proto file separately
  for protoFile in request.protoFile {

    // a package declaration is required
    guard let package = protoFile.package else {
      print("ERROR: no package for \(protoFile.name)")
      continue
    }

    // log info about the service
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

    // generate separate implementation files for client and server
    let context = ["protoFile": protoFile]

    do {
      let clientcode = try templateEnvironment.renderTemplate(name:"client.pb.swift",
                                                              context: context)
      var clientfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
      clientfile.name = package + ".client.pb.swift"
      clientfile.content = stripMarkers(clientcode)
      response.file.append(clientfile)

      let servercode = try templateEnvironment.renderTemplate(name:"server.pb.swift",
                                                              context: context)
      var serverfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
      serverfile.name = package + ".server.pb.swift"
      serverfile.content = stripMarkers(servercode)
      response.file.append(serverfile)
    } catch (let error) {
      log += "ERROR: \(error)\n"
    }
  }

  // add the logfile to the code generation response
  var logfile = Google_Protobuf_Compiler_CodeGeneratorResponse.File()
  logfile.name = "swiftgrpc.log"
  logfile.content = log
  response.file.append(logfile)

  // return everything to the caller
  let serializedResponse = try response.serializeProtobuf()
  Stdout.write(bytes: serializedResponse)
}

try main()
