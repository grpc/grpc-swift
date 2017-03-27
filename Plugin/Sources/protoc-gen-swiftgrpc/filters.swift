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
func protoMessageName(_ name :String?) -> String {
  guard let name = name else {
    return ""
  }

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
  guard let protoFile = arguments[0] as? FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? ServiceDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "ServiceDescriptor" +
        " argument, received \(String(describing:arguments[1]))")
  }
  guard let method = arguments[2] as? MethodDescriptor
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
  guard let protoFile = arguments[0] as? FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? ServiceDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "ServiceDescriptor" +
        " argument, received \(String(describing:arguments[1]))")
  }
  guard let method = arguments[2] as? MethodDescriptor
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
  guard let protoFile = arguments[0] as? FileDescriptor
    else {
      throw TemplateSyntaxError("tag must be called with a " +
        "FileDescriptor" +
        " argument, received \(String(describing:arguments[0]))")
  }
  guard let service = arguments[1] as? ServiceDescriptor
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
	      if let value = value as? MethodDescriptor {
	        return protoMessageName(value.inputType)
	      }
	      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
	    }
	    ext.registerFilter("output") { (value: Any?) in
	      if let value = value as? MethodDescriptor {
	        return protoMessageName(value.outputType)
	      }
	      throw TemplateSyntaxError("message: invalid argument \(String(describing:value))")
	    }
	}
}