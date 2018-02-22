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

let namer = SwiftProtobufNamer()

// internal helpers
extension String {
  var undotted: String {
    return replacingOccurrences(of: ".", with: "_")
  }

  var uppercasedFirst: String {
    var out = characters
    if let first = out.popFirst() {
      return String(first).uppercased() + String(out)
    } else {
      return self
    }
  }
}

// error-generating helpers

func invalidArgumentCount(filter: String, expected: Int) -> TemplateSyntaxError {
  return TemplateSyntaxError("\(filter): expects \(expected) arguments")
}

func invalidArgument(filter: String, value: Any?) -> TemplateSyntaxError {
  return TemplateSyntaxError("\(filter): invalid argument \(String(describing: value))")
}

func invalidArgumentType(filter: String, required: String, received: Any?) -> TemplateSyntaxError {
  return TemplateSyntaxError("\(filter): invalid argument type: required \(required) received \(String(describing: received))")
}

// functions for use in templates

// Transform .some.package_name.FooBarRequest -> Some_PackageName_FooBarRequest
func protoMessageName(_ descriptor: SwiftProtobufPluginLibrary.Descriptor) -> String {
  return namer.fullName(message: descriptor)
}

func pathName(filter _: String, arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw invalidArgumentCount(filter: "path", expected: 3)
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
  else {
    throw invalidArgumentType(filter: "path", required: "FileDescriptor", received: arguments[0])
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
  else {
    throw invalidArgumentType(filter: "path", required: "ServiceDescriptor", received: arguments[1])
  }
  guard let method = arguments[2] as? SwiftProtobufPluginLibrary.MethodDescriptor
  else {
    throw invalidArgumentType(filter: "path", required: "MethodDescriptor", received: arguments[2])
  }
  return "/" + protoFile.package + "." + service.name + "/" + method.name
}

func packageServiceMethodName(filter: String, arguments: [Any?]) throws -> String {
  if arguments.count != 3 {
    throw invalidArgumentCount(filter: "packageServiceMethodName", expected: 3)
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
  else {
    throw invalidArgumentType(filter: filter, required: "FileDescriptor", received: arguments[0])
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
  else {
    throw invalidArgumentType(filter: filter, required: "ServiceDescriptor", received: arguments[0])
  }
  guard let method = arguments[2] as? SwiftProtobufPluginLibrary.MethodDescriptor
  else {
    throw invalidArgumentType(filter: filter, required: "MethodDescriptor", received: arguments[0])
  }
  return protoFile.package.capitalized.undotted + "_" + service.name + method.name
}

func packageServiceName(filter: String, arguments: [Any?]) throws -> String {
  if arguments.count != 2 {
    throw invalidArgumentCount(filter: "packageServiceName", expected: 2)
  }
  guard let protoFile = arguments[0] as? SwiftProtobufPluginLibrary.FileDescriptor
  else {
    throw invalidArgumentType(filter: filter, required: "FileDescriptor", received: arguments[0])
  }
  guard let service = arguments[1] as? SwiftProtobufPluginLibrary.ServiceDescriptor
  else {
    throw invalidArgumentType(filter: filter, required: "ServiceDescriptor", received: arguments[0])
  }
  return protoFile.package.capitalized.undotted + "_" + service.name
}

class GRPCFilterExtension: Extension {
  override init() {
    super.init()
    // initialize template engine and add custom filters
    let ext = self
    ext.registerFilter("call") { (_: Any?, arguments: [Any?]) in
      return try packageServiceMethodName(filter: "call", arguments: arguments) + "Call"
    }
    ext.registerFilter("session") { (_: Any?, arguments: [Any?]) in
      return try packageServiceMethodName(filter: "session", arguments: arguments) + "Session"
    }
    ext.registerFilter("path") { (_: Any?, arguments: [Any?]) in
      return try pathName(filter: "path", arguments: arguments)
    }
    ext.registerFilter("provider") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "provider", arguments: arguments) + "Provider"
    }
    ext.registerFilter("clienterror") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "clienterror", arguments: arguments) + "ClientError"
    }
    ext.registerFilter("serviceclass") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "serviceclass", arguments: arguments) + "Service"
    }
    ext.registerFilter("servererror") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "servererror", arguments: arguments) + "ServerError"
    }
    ext.registerFilter("server") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "server", arguments: arguments) + "Server"
    }
    ext.registerFilter("service") { (_: Any?, arguments: [Any?]) in
      return try packageServiceName(filter: "server", arguments: arguments)
    }
    ext.registerFilter("input") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return protoMessageName(value.inputType)
      }
      throw invalidArgumentType(filter: "input", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("output") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return protoMessageName(value.outputType)
      }
      throw invalidArgumentType(filter: "output", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("fileDescriptorName") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.FileDescriptor {
        return value.name
      }
      throw invalidArgumentType(filter: "fileDescriptorName", required: "FileDescriptor", received: value)
    }
    ext.registerFilter("methodDescriptorName") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.name
      }
      throw invalidArgumentType(filter: "methodDescriptorName", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("methodIsUnary") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return !value.proto.clientStreaming && !value.proto.serverStreaming
      }
      throw invalidArgumentType(filter: "methodIsUnary", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("methodIsServerStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return !value.proto.clientStreaming && value.proto.serverStreaming
      }
      throw invalidArgumentType(filter: "methodIsServerStreaming", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("methodIsClientStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.proto.clientStreaming && !value.proto.serverStreaming
      }
      throw invalidArgumentType(filter: "methodIsClientStreaming", required: "MethodDescriptor", received: value)
    }
    ext.registerFilter("methodIsBidiStreaming") { (value: Any?) in
      if let value = value as? SwiftProtobufPluginLibrary.MethodDescriptor {
        return value.proto.clientStreaming && value.proto.serverStreaming
      }
      throw invalidArgumentType(filter: "methodIsBidiStreaming", required: "MethodDescriptor", received: value)
    }
  }
}
