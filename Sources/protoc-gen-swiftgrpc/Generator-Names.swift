/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

// Transform .some.package_name.FooBarRequest -> Some_PackageName_FooBarRequest
internal func protoMessageName(_ descriptor: SwiftProtobufPluginLibrary.Descriptor) -> String {
  return SwiftProtobufNamer().fullName(message: descriptor)
}

internal func nameForPackageService(_ file: FileDescriptor,
                                    _ service: ServiceDescriptor) -> String {
  if !file.package.isEmpty {
    return SwiftProtobufNamer().typePrefix(forFile:file) + service.name
  } else {
    return service.name
  }
}

internal func nameForPackageServiceMethod(_ file: FileDescriptor,
                                          _ service: ServiceDescriptor,
                                          _ method: MethodDescriptor) -> String {
  return nameForPackageService(file, service) + method.name
}

extension Generator {

  internal var access : String {
    return options.visibility.sourceSnippet
  }

  internal var serviceClassName: String {
    return nameForPackageService(file, service) + "Service"
  }

  internal var providerName: String {
    return nameForPackageService(file, service) + "Provider"
  }

  internal var serverName: String {
    return nameForPackageService(file, service) + "Server"
  }

  internal var callName: String {
    return nameForPackageServiceMethod(file, service, method) + "Call"
  }

  internal var methodFunctionName: String {
    let name = method.name
    return name.prefix(1).lowercased() + name.dropFirst()
  }

  internal var methodSessionName: String {
    return nameForPackageServiceMethod(file, service, method) + "Session"
  }

  internal var methodInputName: String {
    return protoMessageName(method.inputType)
  }

  internal var methodOutputName: String {
    return protoMessageName(method.outputType)
  }

  internal var methodPath: String {
    if !file.package.isEmpty {
      return "\"/" + file.package + "." + service.name + "/" + method.name + "\""
    } else {
      return "\"/" + service.name + "/" + method.name + "\""
    }
  }
}
