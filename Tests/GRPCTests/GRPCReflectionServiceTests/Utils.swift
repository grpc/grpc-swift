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
import GRPCReflectionService
import NIOPosix
import SwiftProtobuf

public func generateProto(name: String, id: Int) -> Google_Protobuf_FileDescriptorProto {
  let inputMessage = Google_Protobuf_DescriptorProto.with {
    $0.name = "inputMessage"
    $0.field = [
      Google_Protobuf_FieldDescriptorProto.with {
        $0.name = "inputField"
        $0.type = .bool
      }
    ]
  }

  let outputMessage = Google_Protobuf_DescriptorProto.with {
    $0.name = "outputMessage"
    $0.field = [
      Google_Protobuf_FieldDescriptorProto.with {
        $0.name = "outputField"
        $0.type = .int32
      }
    ]
  }

  let enumType = Google_Protobuf_EnumDescriptorProto.with {
    $0.name = "enumType" + String(id)
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
    $0.name = "testMethod" + String(id)
    $0.inputType = inputMessage.name
    $0.outputType = outputMessage.name
  }

  let serviceDescriptor = Google_Protobuf_ServiceDescriptorProto.with {
    $0.method = [method]
    $0.name = "service" + String(id)
  }

  let fileDescriptorProto = Google_Protobuf_FileDescriptorProto.with {
    $0.service = [serviceDescriptor]
    $0.name = name + String(id) + ".proto"
    $0.package = "package" + name + String(id)
    $0.messageType = [inputMessage, outputMessage]
    $0.enumType = [enumType]
  }

  return fileDescriptorProto
}

/// Creates the dependencies of the proto used in the testing context.
public func makeProtosWithDependencies() -> [Google_Protobuf_FileDescriptorProto] {
  var fileDependencies: [Google_Protobuf_FileDescriptorProto] = []
  for id in 1 ... 4 {
    let fileDescriptorProto = generateProto(name: "bar", id: id)
    if id != 1 {
      // Dependency of the first dependency.
      fileDependencies[0].dependency.append(fileDescriptorProto.name)
    }
    fileDependencies.append(fileDescriptorProto)
  }
  return fileDependencies
}

public func makeProtosWithComplexDependencies() -> [Google_Protobuf_FileDescriptorProto] {
  var protos: [Google_Protobuf_FileDescriptorProto] = []
  protos.append(generateProto(name: "foo", id: 0))
  for id in 1 ... 10 {
    let fileDescriptorProtoA = generateProto(name: "fooA", id: id)
    let fileDescriptorProtoB = generateProto(name: "fooB", id: id)
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
