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

let namer = SwiftProtobufNamer()

// internal helpers
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

// functions for use in templates

// Transform .some.package_name.FooBarRequest -> Some_PackageName_FooBarRequest
func protoMessageName(_ descriptor :SwiftProtobufPluginLibrary.Descriptor) -> String {
  let name = descriptor.fullName 

  var parts : [String] = []
  for dotComponent in name.components(separatedBy:".") {
    var part = ""
    if dotComponent == "" {
      continue
    }
    for underscoreComponent in dotComponent.components(separatedBy:"_") {
      part.append(underscoreComponent.uppercasedFirst)
    }
    parts.append(part)
  }

  return parts.joined(separator:"_")
}

func pathName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw TemplateSyntaxError("path expects 3 arguments")
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "ServiceDescriptor" +
        " argument, received \(String(describing:arguments[1]))")
  }
  guard let method = arguments[2] as? SwiftProtobufPluginLibrary.MethodDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "MethodDescriptor" +
        " argument, received \(String(describing:arguments[2]))")
  }
  return "/" + protoFile.package + "." + service.name + "/" + method.name
}

func packageServiceMethodName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw TemplateSyntaxError("tag expects 3 arguments")
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "ServiceDescriptor" +
        " argument, received \(String(describing:arguments[1]))")
  }
  guard let method = arguments[2] as? SwiftProtobufPluginLibrary.MethodDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "MethodDescriptor" +
        " argument, received \(String(describing:arguments[2]))")
  }
  return protoFile.package.capitalized.undotted + "_" + service.name + method.name
}

func packageServiceName(_ arguments: [Any?]) throws -> String {
  if arguments.count != 2 {
    throw TemplateSyntaxError("tag expects 2 arguments")
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "ServiceDescriptor" +
        " argument, received \(String(describing:arguments[1]))")
  }
  return protoFile.package.capitalized.undotted + "_" + service.name
}

class GRPCFilterExtension : Extension {
  override init() {
    super.init()
    // initialize template engine and add custom filters
    let ext = self
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
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return protoMessageName(value.inputType)
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("output") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return protoMessageName(value.outputType)
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("fileDescriptorName") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.FileDescriptor {
        return value.name
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("methodDescriptorName") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.name
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("methodIsUnary") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return !value.proto.clientStreaming && !value.proto.serverStreaming
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("methodIsServerStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return !value.proto.clientStreaming && value.proto.serverStreaming
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("methodIsClientStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.proto.clientStreaming && !value.proto.serverStreaming
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
    ext.registerFilter("methodIsBidiStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.proto.clientStreaming && value.proto.serverStreaming
      }
      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
    }
  }
}
