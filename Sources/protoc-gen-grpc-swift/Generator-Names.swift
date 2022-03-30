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

internal func nameForPackageService(
  _ file: FileDescriptor,
  _ service: ServiceDescriptor
) -> String {
  if !file.package.isEmpty {
    return SwiftProtobufNamer().typePrefix(forFile: file) + service.name
  } else {
    return service.name
  }
}

internal func nameForPackageServiceMethod(
  _ file: FileDescriptor,
  _ service: ServiceDescriptor,
  _ method: MethodDescriptor
) -> String {
  return nameForPackageService(file, service) + method.name
}

private let swiftKeywordsUsedInDeclarations: Set<String> = [
  "associatedtype", "class", "deinit", "enum", "extension",
  "fileprivate", "func", "import", "init", "inout", "internal",
  "let", "open", "operator", "private", "protocol", "public",
  "static", "struct", "subscript", "typealias", "var",
]

private let swiftKeywordsUsedInStatements: Set<String> = [
  "break", "case",
  "continue", "default", "defer", "do", "else", "fallthrough",
  "for", "guard", "if", "in", "repeat", "return", "switch", "where",
  "while",
]

private let swiftKeywordsUsedInExpressionsAndTypes: Set<String> = [
  "as",
  "Any", "catch", "false", "is", "nil", "rethrows", "super", "self",
  "Self", "throw", "throws", "true", "try",
]

private let quotableFieldNames: Set<String> = { () -> Set<String> in
  var names: Set<String> = []

  names = names.union(swiftKeywordsUsedInDeclarations)
  names = names.union(swiftKeywordsUsedInStatements)
  names = names.union(swiftKeywordsUsedInExpressionsAndTypes)
  return names
}()

extension Generator {
  internal var access: String {
    return options.visibility.sourceSnippet
  }

  internal var serviceClassName: String {
    return nameForPackageService(file, service) + "Service"
  }

  internal var providerName: String {
    return nameForPackageService(file, service) + "Provider"
  }

  internal var asyncProviderName: String {
    return nameForPackageService(file, service) + "AsyncProvider"
  }

  internal var clientClassName: String {
    return nameForPackageService(file, service) + "Client"
  }

  internal var asyncClientClassName: String {
    return nameForPackageService(file, service) + "AsyncClient"
  }

  internal var testClientClassName: String {
    return nameForPackageService(self.file, self.service) + "TestClient"
  }

  internal var clientProtocolName: String {
    return nameForPackageService(file, service) + "ClientProtocol"
  }

  internal var asyncClientProtocolName: String {
    return nameForPackageService(file, service) + "AsyncClientProtocol"
  }

  internal var clientInterceptorProtocolName: String {
    return nameForPackageService(file, service) + "ClientInterceptorFactoryProtocol"
  }

  internal var serverInterceptorProtocolName: String {
    return nameForPackageService(file, service) + "ServerInterceptorFactoryProtocol"
  }

  internal var callName: String {
    return nameForPackageServiceMethod(file, service, method) + "Call"
  }

  internal var methodFunctionName: String {
    var name = method.name
    if !self.options.keepMethodCasing {
      name = name.prefix(1).lowercased() + name.dropFirst()
    }

    return self.sanitize(fieldName: name)
  }

  internal var methodMakeFunctionCallName: String {
    let name: String

    if self.options.keepMethodCasing {
      name = self.method.name
    } else {
      name = NamingUtils.toUpperCamelCase(self.method.name)
    }

    let fnName = "make\(name)Call"
    return self.sanitize(fieldName: fnName)
  }

  internal func sanitize(fieldName string: String) -> String {
    if quotableFieldNames.contains(string) {
      return "`\(string)`"
    }
    return string
  }

  internal var methodInputName: String {
    return protobufNamer.fullName(message: method.inputType)
  }

  internal var methodOutputName: String {
    return protobufNamer.fullName(message: method.outputType)
  }

  internal var methodInterceptorFactoryName: String {
    return "make\(self.method.name)Interceptors"
  }

  internal var servicePath: String {
    if !file.package.isEmpty {
      return file.package + "." + service.name
    } else {
      return service.name
    }
  }

  internal var methodPath: String {
    return "/" + self.fullMethodName
  }

  internal var fullMethodName: String {
    return self.servicePath + "/" + self.method.name
  }
}

internal func quoted(_ str: String) -> String {
  return "\"" + str + "\""
}
