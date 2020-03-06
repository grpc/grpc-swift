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

  internal var clientClassName: String {
    return nameForPackageService(file, service) + "Client"
  }

  internal var clientProtocolName: String {
    return nameForPackageService(file, service) + "ClientProtocol"
  }

  internal var callName: String {
    return nameForPackageServiceMethod(file, service, method) + "Call"
  }

  internal var methodFunctionName: String {
    let name = method.name
    return name.prefix(1).lowercased() + name.dropFirst()
  }

  internal var methodInputName: String {
    return protobufNamer.fullName(message: method.inputType)
  }

  internal var methodOutputName: String {
    return protobufNamer.fullName(message: method.outputType)
  }
  
  internal var servicePath: String {
    if !file.package.isEmpty {
      return file.package + "." + service.name
    } else {
      return service.name
    }
  }

  internal var methodPath: String {
    return "\"/" + servicePath + "/" + method.name + "\""
  }
}
