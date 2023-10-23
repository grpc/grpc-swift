/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import GRPC
import SwiftProtobuf

internal func makeExtensions(
  forType typeName: String,
  number: Int
) -> [Google_Protobuf_FieldDescriptorProto] {
  var extensions: [Google_Protobuf_FieldDescriptorProto] = []
  for id in 1 ... number {
    extensions.append(
      Google_Protobuf_FieldDescriptorProto.with {
        $0.name = "extension" + typeName + "-" + String(id)
        $0.extendee = typeName
        $0.number = Int32(id)
      }
    )
  }
  return extensions
}

internal func generateFileDescriptorProto(
  fileName name: String,
  suffix: String
) -> Google_Protobuf_FileDescriptorProto {
  let inputMessage = Google_Protobuf_DescriptorProto.with {
    $0.name = "inputMessage" + suffix
    $0.field = [
      Google_Protobuf_FieldDescriptorProto.with {
        $0.name = "inputField"
        $0.type = .bool
      }
    ]
  }

  let packageName = "package" + name + suffix
  let inputMessageExtensions = makeExtensions(
    forType: "." + packageName + "." + "inputMessage" + suffix,
    number: 5
  )

  let outputMessage = Google_Protobuf_DescriptorProto.with {
    $0.name = "outputMessage" + suffix
    $0.field = [
      Google_Protobuf_FieldDescriptorProto.with {
        $0.name = "outputField"
        $0.type = .int32
      }
    ]
  }

  let enumType = Google_Protobuf_EnumDescriptorProto.with {
    $0.name = "enumType" + suffix
    $0.value = [
      Google_Protobuf_EnumValueDescriptorProto.with {
        $0.name = "value1"
      },
      Google_Protobuf_EnumValueDescriptorProto.with {
        $0.name = "value2"
      },
    ]
  }

  let method = Google_Protobuf_MethodDescriptorProto.with {
    $0.name = "testMethod" + suffix
    $0.inputType = inputMessage.name
    $0.outputType = outputMessage.name
  }

  let serviceDescriptor = Google_Protobuf_ServiceDescriptorProto.with {
    $0.method = [method]
    $0.name = "service" + suffix
  }

  let fileDescriptorProto = Google_Protobuf_FileDescriptorProto.with {
    $0.service = [serviceDescriptor]
    $0.name = name + suffix + ".proto"
    $0.package = "package" + name + suffix
    $0.messageType = [inputMessage, outputMessage]
    $0.enumType = [enumType]
    $0.extension = inputMessageExtensions
  }

  return fileDescriptorProto
}

/// Creates the dependencies of the proto used in the testing context.
internal func makeProtosWithDependencies() -> [Google_Protobuf_FileDescriptorProto] {
  var fileDependencies: [Google_Protobuf_FileDescriptorProto] = []
  for id in 1 ... 4 {
    let fileDescriptorProto = generateFileDescriptorProto(fileName: "bar", suffix: String(id))
    if id != 1 {
      // Dependency of the first dependency.
      fileDependencies[0].dependency.append(fileDescriptorProto.name)
    }
    fileDependencies.append(fileDescriptorProto)
  }
  return fileDependencies
}

internal func makeProtosWithComplexDependencies() -> [Google_Protobuf_FileDescriptorProto] {
  var protos: [Google_Protobuf_FileDescriptorProto] = []
  protos.append(generateFileDescriptorProto(fileName: "foo", suffix: "0"))
  for id in 1 ... 10 {
    let fileDescriptorProtoA = generateFileDescriptorProto(
      fileName: "fooA",
      suffix: String(id) + "A"
    )
    let fileDescriptorProtoB = generateFileDescriptorProto(
      fileName: "fooB",
      suffix: String(id) + "B"
    )

    let parent = protos.count > 1 ? protos.count - Int.random(in: 1 ..< 3) : protos.count - 1
    protos[parent].dependency.append(fileDescriptorProtoA.name)
    protos[parent].dependency.append(fileDescriptorProtoB.name)
    protos.append(fileDescriptorProtoA)
    protos.append(fileDescriptorProtoB)
  }
  return protos
}

extension Sequence where Element == Google_Protobuf_FileDescriptorProto {
  var serviceNames: [String] {
    self.flatMap { $0.service.map { $0.name } }
  }
}

extension Sequence where Element == Google_Protobuf_EnumDescriptorProto {
  var names: [String] {
    self.map { $0.name }
  }
}
