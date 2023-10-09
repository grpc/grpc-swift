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

public struct ReflectionServiceData: Sendable {
  public struct protoData: Sendable {
    fileprivate var serializedFileDescriptorProto: Data = .init()
    fileprivate var dependency: [String] = []
    fileprivate init() {}
    public func getSerializedFileDescriptorProto() -> Data {
      self.serializedFileDescriptorProto
    }

    public func getDependency() -> [String] {
      self.dependency
    }
  }

  private let fileDescriptorData: [String: protoData]
  private let services: [String]

  public init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto]) throws {
    var fileDescriptorDataAux: [String: protoData] = [:]
    var servicesAux: [String] = []

    for fileDescriptorProto in fileDescriptorProtos {
      var protoDataObj = protoData()
      protoDataObj.serializedFileDescriptorProto = try fileDescriptorProto.serializedData()
      protoDataObj.dependency = fileDescriptorProto.dependency
      fileDescriptorDataAux[fileDescriptorProto.name] = protoDataObj

      servicesAux.append(contentsOf: fileDescriptorProto.service.map { $0.name })
    }
    self.fileDescriptorData = fileDescriptorDataAux
    self.services = servicesAux
  }

  public func getSerializedFileDescriptorProtos(fileName: String) throws -> [Data] {
    var toVisit: [String] = []
    var visited: [String] = []
    var serializedFileDescriptorProtos: [Data] = []
    toVisit.append(fileName)

    while (!toVisit.isEmpty) {
      let currentFileName = toVisit.removeFirst()
      let protoData = self.fileDescriptorData[currentFileName]
      if (protoData != nil) {
        let serializedFileDescriptorProto = protoData!.serializedFileDescriptorProto
        if (!protoData!.dependency.isEmpty) {
          toVisit
            .append(
              contentsOf: self.fileDescriptorData[currentFileName]!.dependency
                .filter { name in
                  return !visited.contains(name)
                }
            )
        }
        serializedFileDescriptorProtos.append(serializedFileDescriptorProto)
      } else {
        throw GRPCStatus(
          code: .invalidArgument,
          message: "The provided file name for the proto file is not valid."
        )
      }
      visited.append(currentFileName)
    }
    return serializedFileDescriptorProtos
  }

  public func getServices() -> [String] {
    return self.services
  }

  public func getfileDescriptorData() -> [String: protoData] {
    return self.fileDescriptorData
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class ReflectionService: Reflection_ServerReflectionAsyncProvider {
  private let protoRegistry: ReflectionServiceData
  public init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto]) throws {
    do {
      self
        .protoRegistry = try ReflectionServiceData(fileDescriptorProtos: fileDescriptorProtos)
    } catch {
      throw GRPCStatus(code: .invalidArgument, message: error.localizedDescription)
    }
  }

  internal func createServerReflectionResponse(
    request: Reflection_ServerReflectionRequest,
    fileDescriptorResponse: Reflection_FileDescriptorResponse
  ) -> Reflection_ServerReflectionResponse {
    let response = Reflection_ServerReflectionResponse.with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.fileDescriptorResponse = fileDescriptorResponse
    }
    return response
  }

  internal func createServerReflectionResponse(
    request: Reflection_ServerReflectionRequest,
    listServicesResponse: Reflection_ListServiceResponse
  ) -> Reflection_ServerReflectionResponse {
    let response = Reflection_ServerReflectionResponse.with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.listServicesResponse = listServicesResponse
    }
    return response
  }

  internal func createFileDescriptorResponse(
    fileName: String,
    request: Reflection_ServerReflectionRequest
  ) throws -> Reflection_ServerReflectionResponse {
    var fileDescriptorResponse = Reflection_FileDescriptorResponse()
    fileDescriptorResponse.fileDescriptorProto = try self.protoRegistry
      .getSerializedFileDescriptorProtos(fileName: fileName)
    return self.createServerReflectionResponse(
      request: request,
      fileDescriptorResponse: fileDescriptorResponse
    )
  }

  internal func createListServicesResponse(request: Reflection_ServerReflectionRequest) throws ->
    Reflection_ServerReflectionResponse {
    var listServicesResponse = Reflection_ListServiceResponse()
    listServicesResponse.service = self.protoRegistry.getServices().map({ serviceName in
      let serviceResponse = Reflection_ServiceResponse.with {
        $0.name = serviceName
      }
      return serviceResponse
    })
    let response = Reflection_ServerReflectionResponse.with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.listServicesResponse = listServicesResponse
    }
    return response
  }

  public func serverReflectionInfo(
    requestStream: GRPCAsyncRequestStream<Reflection_ServerReflectionRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Reflection_ServerReflectionResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await request in requestStream {
      switch request.messageRequest {
      case let .fileByFilename(fileName):
        let response = try createFileDescriptorResponse(
          fileName: fileName,
          request: request
        )
        try await responseStream.send(response)
      case .listServices:
        let response = try createListServicesResponse(request: request)
        try await responseStream.send(response)
      default:
        throw GRPCStatus(code: .unimplemented)
      }
    }
    throw GRPCStatus(code: .unimplemented)
  }
}
