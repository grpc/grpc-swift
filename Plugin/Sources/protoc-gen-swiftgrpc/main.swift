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

extension String {
  var undotted : String {
    return self.replacingOccurrences(of:".", with:"_")
  }

  var uppercasedFirst : String {
    var out = self.characters
    if let first = out.popFirst() {
      return String(first).uppercased() + String(out)
    } else {
      return self
    }
  }
}

func protoMessageName(_ name :String?) -> String {
  guard let name = name else {
    return ""
  }
  let parts = name.undotted.components(separatedBy:"_")
  var capitalizedParts : [String] = []
  for part in parts {
    if part != "" {
      capitalizedParts.append(part.uppercasedFirst)
    }
  }
  return capitalizedParts.joined(separator:"_")
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
  return protoFile.package!.capitalized.undotted + "_" + service.name! + method.name!
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
  return protoFile.package!.capitalized.undotted + "_" + service.name!
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

func Log(_ message : String) {
  FileHandle.standardError.write((message + "\n").data(using:.utf8)!)
}

func main() throws {

  // initialize template engine and add custom filters
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
  ext.registerFilter("serviceclass") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "Service"
  }
  ext.registerFilter("servererror") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "ServerError"
  }
  ext.registerFilter("server") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments) + "Server"
  }
  ext.registerFilter("service") { (value: Any?, arguments: [Any?]) in
    return try packageServiceName(arguments)
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
  let templateEnvironment = Environment(loader: InternalLoader(),
                                        extensions:[ext])

  // initialize responses
  var response = Google_Protobuf_Compiler_CodeGeneratorResponse()
  var log = ""

  // read plugin input
  let rawRequest = try Stdin.readall()
  let request = try Google_Protobuf_Compiler_CodeGeneratorRequest(protobuf: rawRequest)

  var generatedFileNames = Set<String>()
  
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

    if protoFile.service.count > 0 {
    // generate separate implementation files for client and server
    let context = ["protoFile": protoFile]

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
  let serializedResponse = try response.serializeProtobuf()
  Stdout.write(bytes: serializedResponse)
}

do {
	try main()	
} catch (let error) {
	Log("ERROR: \(error)")	
}
