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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class ReflectionServiceProviderV1Alpha:
  Grpc_Reflection_V1alpha_ServerReflectionAsyncProvider
{
  private let protoRegistry: ReflectionServiceData

  internal init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto]) throws {
    self.protoRegistry = try ReflectionServiceData(
      fileDescriptors: fileDescriptorProtos
    )
  }

  internal func _findFileByFileName(
    _ fileName: String
  ) -> Result<Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse, GRPCStatus> {
    return self.protoRegistry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: fileName)
      .map { fileDescriptorProtos in
        Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse
          .fileDescriptorResponse(
            .with {
              $0.fileDescriptorProto = fileDescriptorProtos
            }
          )
      }
  }

  internal func findFileByFileName(
    _ fileName: String,
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    let result = self._findFileByFileName(fileName)
    return result.makeResponse(request: request)
  }

  internal func getServicesNames(
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) throws -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    var listServicesResponse = Grpc_Reflection_V1alpha_ListServiceResponse()
    listServicesResponse.service = self.protoRegistry.serviceNames.map { serviceName in
      Grpc_Reflection_V1alpha_ServiceResponse.with {
        $0.name = serviceName
      }
    }
    return Grpc_Reflection_V1alpha_ServerReflectionResponse(
      request: request,
      messageResponse: .listServicesResponse(listServicesResponse)
    )
  }

  internal func findFileBySymbol(
    _ symbolName: String,
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    let result = self.protoRegistry.nameOfFileContainingSymbol(
      named: symbolName
    ).flatMap {
      self._findFileByFileName($0)
    }
    return result.makeResponse(request: request)
  }

  internal func findFileByExtension(
    extensionRequest: Grpc_Reflection_V1alpha_ExtensionRequest,
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    let result = self.protoRegistry.nameOfFileContainingExtension(
      extendeeName: extensionRequest.containingType,
      fieldNumber: extensionRequest.extensionNumber
    ).flatMap {
      self._findFileByFileName($0)
    }
    return result.makeResponse(request: request)
  }

  internal func findExtensionsFieldNumbersOfType(
    named typeName: String,
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    let result = self.protoRegistry.extensionsFieldNumbersOfType(
      named: typeName
    ).map { fieldNumbers in
      Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse
        .allExtensionNumbersResponse(
          Grpc_Reflection_V1alpha_ExtensionNumberResponse.with {
            $0.baseTypeName = typeName
            $0.extensionNumber = fieldNumbers
          }
        )
    }
    return result.makeResponse(request: request)
  }

  internal func serverReflectionInfo(
    requestStream: GRPCAsyncRequestStream<Grpc_Reflection_V1alpha_ServerReflectionRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Reflection_V1alpha_ServerReflectionResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await request in requestStream {
      switch request.messageRequest {
      case let .fileByFilename(fileName):
        let response = self.findFileByFileName(
          fileName,
          request: request
        )
        try await responseStream.send(response)

      case .listServices:
        let response = try self.getServicesNames(request: request)
        try await responseStream.send(response)

      case let .fileContainingSymbol(symbolName):
        let response = self.findFileBySymbol(
          symbolName,
          request: request
        )
        try await responseStream.send(response)

      case let .fileContainingExtension(extensionRequest):
        let response = self.findFileByExtension(
          extensionRequest: extensionRequest,
          request: request
        )
        try await responseStream.send(response)

      case let .allExtensionNumbersOfType(typeName):
        let response = self.findExtensionsFieldNumbersOfType(
          named: typeName,
          request: request
        )
        try await responseStream.send(response)

      default:
        let response = Grpc_Reflection_V1alpha_ServerReflectionResponse(
          request: request,
          messageResponse: .errorResponse(
            Grpc_Reflection_V1alpha_ErrorResponse.with {
              $0.errorCode = Int32(GRPCStatus.Code.unimplemented.rawValue)
              $0.errorMessage = "The request is not implemented."
            }
          )
        )
        try await responseStream.send(response)
      }
    }
  }
}

extension Grpc_Reflection_V1alpha_ServerReflectionResponse {
  init(
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest,
    messageResponse: Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse
  ) {
    self = .with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.messageResponse = messageResponse
    }
  }
}

extension Result<Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse, GRPCStatus>
{
  func recover() -> Result<
    Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse, Never
  > {
    self.flatMapError { status in
      let error = Grpc_Reflection_V1alpha_ErrorResponse.with {
        $0.errorCode = Int32(status.code.rawValue)
        $0.errorMessage = status.message ?? ""
      }
      return .success(.errorResponse(error))
    }
  }

  func makeResponse(
    request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Grpc_Reflection_V1alpha_ServerReflectionResponse {
    let result = self.recover().attachRequest(request)
    // Safe to '!' as the failure type is 'Never'.
    return try! result.get()
  }
}

extension Result
where Success == Grpc_Reflection_V1alpha_ServerReflectionResponse.OneOf_MessageResponse {
  func attachRequest(
    _ request: Grpc_Reflection_V1alpha_ServerReflectionRequest
  ) -> Result<Grpc_Reflection_V1alpha_ServerReflectionResponse, Failure> {
    self.map { message in
      Grpc_Reflection_V1alpha_ServerReflectionResponse(request: request, messageResponse: message)
    }
  }
}
