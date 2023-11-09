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
import XCTest

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

func XCTAssertThrowsGRPCStatus<T>(
  _ expression: @autoclosure () throws -> T,
  _ errorHandler: (GRPCStatus) -> Void
) {
  XCTAssertThrowsError(try expression()) { error in
    guard let error = error as? GRPCStatus else {
      return XCTFail("Error had unexpected type '\(type(of: error))'")
    }

    errorHandler(error)
  }
}

extension Google_Protobuf_FileDescriptorProto {
  var qualifiedServiceNames: [String] {
    self.service.map { self.package + "." + $0.name }
  }
}

extension Sequence where Element == Google_Protobuf_EnumDescriptorProto {
  var names: [String] {
    self.map { $0.name }
  }
}

extension Grpc_Reflection_V1_ExtensionRequest {
  init(_ v1AlphaExtensionRequest: Grpc_Reflection_V1alpha_ExtensionRequest) {
    self = .with {
      $0.containingType = v1AlphaExtensionRequest.containingType
      $0.extensionNumber = v1AlphaExtensionRequest.extensionNumber
      $0.unknownFields = v1AlphaExtensionRequest.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionRequest.OneOf_MessageRequest? {
  init(_ v1AlphaRequest: Grpc_Reflection_V1alpha_ServerReflectionRequest) {
    guard let messageRequest = v1AlphaRequest.messageRequest else {
      self = nil
      return
    }
    switch messageRequest {
    case .allExtensionNumbersOfType(let typeName):
      self = .allExtensionNumbersOfType(typeName)
    case .fileByFilename(let fileName):
      self = .fileByFilename(fileName)
    case .fileContainingSymbol(let symbol):
      self = .fileContainingSymbol(symbol)
    case .fileContainingExtension(let v1AlphaExtensionRequest):
      self = .fileContainingExtension(
        Grpc_Reflection_V1_ExtensionRequest(v1AlphaExtensionRequest)
      )
    case .listServices(let parameter):
      self = .listServices(parameter)
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionRequest {
  init(_ v1AlphaRequest: Grpc_Reflection_V1alpha_ServerReflectionRequest) {
    self = .with {
      $0.host = v1AlphaRequest.host
      $0.messageRequest = Grpc_Reflection_V1_ServerReflectionRequest.OneOf_MessageRequest?(
        v1AlphaRequest
      )
    }
  }
}

extension Grpc_Reflection_V1_FileDescriptorResponse {
  init(_ v1AlphaFileDescriptorResponse: Grpc_Reflection_V1alpha_FileDescriptorResponse) {
    self = .with {
      $0.fileDescriptorProto = v1AlphaFileDescriptorResponse.fileDescriptorProto
      $0.unknownFields = v1AlphaFileDescriptorResponse.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ExtensionNumberResponse {
  init(_ v1AlphaExtensionNumberResponse: Grpc_Reflection_V1alpha_ExtensionNumberResponse) {
    self = .with {
      $0.baseTypeName = v1AlphaExtensionNumberResponse.baseTypeName
      $0.extensionNumber = v1AlphaExtensionNumberResponse.extensionNumber
      $0.unknownFields = v1AlphaExtensionNumberResponse.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ServiceResponse {
  init(_ v1AlphaServiceResponse: Grpc_Reflection_V1alpha_ServiceResponse) {
    self = .with {
      $0.name = v1AlphaServiceResponse.name
      $0.unknownFields = v1AlphaServiceResponse.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ListServiceResponse {
  init(_ v1AlphaListServicesResponse: Grpc_Reflection_V1alpha_ListServiceResponse) {
    self = .with {
      $0.service = v1AlphaListServicesResponse.service.map {
        Grpc_Reflection_V1_ServiceResponse($0)
      }
      $0.unknownFields = v1AlphaListServicesResponse.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ErrorResponse {
  init(_ v1AlphaErrorResponse: Grpc_Reflection_V1alpha_ErrorResponse) {
    self = .with {
      $0.errorCode = v1AlphaErrorResponse.errorCode
      $0.errorMessage = v1AlphaErrorResponse.errorMessage
      $0.unknownFields = v1AlphaErrorResponse.unknownFields
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionResponse.OneOf_MessageResponse? {
  init(_ v1AlphaResponse: Grpc_Reflection_V1alpha_ServerReflectionResponse) {
    guard let messageRequest = v1AlphaResponse.messageResponse else {
      self = nil
      return
    }
    switch messageRequest {
    case .fileDescriptorResponse(let v1AlphaFileDescriptorResponse):
      self = .fileDescriptorResponse(
        Grpc_Reflection_V1_FileDescriptorResponse(
          v1AlphaFileDescriptorResponse
        )
      )
    case .allExtensionNumbersResponse(let v1AlphaAllExtensionNumbersResponse):
      self = .allExtensionNumbersResponse(
        Grpc_Reflection_V1_ExtensionNumberResponse(
          v1AlphaAllExtensionNumbersResponse
        )
      )
    case .listServicesResponse(let v1AlphaListServicesResponse):
      self = .listServicesResponse(
        Grpc_Reflection_V1_ListServiceResponse(
          v1AlphaListServicesResponse
        )
      )
    case .errorResponse(let v1AlphaErrorResponse):
      self = .errorResponse(
        Grpc_Reflection_V1_ErrorResponse(v1AlphaErrorResponse)
      )
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionResponse {
  init(_ v1AlphaResponse: Grpc_Reflection_V1alpha_ServerReflectionResponse) {
    self = .with {
      $0.validHost = v1AlphaResponse.validHost
      $0.originalRequest = Grpc_Reflection_V1_ServerReflectionRequest(
        v1AlphaResponse.originalRequest
      )
      $0.messageResponse = Grpc_Reflection_V1_ServerReflectionResponse.OneOf_MessageResponse?(
        v1AlphaResponse
      )
    }
  }
}

extension Grpc_Reflection_V1alpha_ExtensionRequest {
  init(_ v1ExtensionRequest: Grpc_Reflection_V1_ExtensionRequest) {
    self = .with {
      $0.containingType = v1ExtensionRequest.containingType
      $0.extensionNumber = v1ExtensionRequest.extensionNumber
      $0.unknownFields = v1ExtensionRequest.unknownFields
    }
  }
}

extension Grpc_Reflection_V1alpha_ServerReflectionRequest.OneOf_MessageRequest? {
  init(_ v1Request: Grpc_Reflection_V1_ServerReflectionRequest) {
    guard let messageRequest = v1Request.messageRequest else {
      self = nil
      return
    }
    switch messageRequest {
    case .allExtensionNumbersOfType(let typeName):
      self = .allExtensionNumbersOfType(typeName)
    case .fileByFilename(let fileName):
      self = .fileByFilename(fileName)
    case .fileContainingSymbol(let symbol):
      self = .fileContainingSymbol(symbol)
    case .fileContainingExtension(let v1ExtensionRequest):
      self = .fileContainingExtension(
        Grpc_Reflection_V1alpha_ExtensionRequest(v1ExtensionRequest)
      )
    case .listServices(let parameter):
      self = .listServices(parameter)
    }
  }
}

extension Grpc_Reflection_V1alpha_ServerReflectionRequest {
  init(_ v1Request: Grpc_Reflection_V1_ServerReflectionRequest) {
    self = .with {
      $0.host = v1Request.host
      $0.messageRequest = Grpc_Reflection_V1alpha_ServerReflectionRequest.OneOf_MessageRequest?(
        v1Request
      )
    }
  }
}
