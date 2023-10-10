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

import DequeModule
import Foundation
import GRPC
import SwiftProtobuf

internal struct ReflectionServiceData: Sendable {
  internal struct FileDescriptorProtoData: Sendable {
    internal let serializedFileDescriptorProto: Data
    internal let dependencyNames: [String]
    internal init(serializedFileDescriptorProto: Data, dependenciesNames: [String]) {
      self.serializedFileDescriptorProto = serializedFileDescriptorProto
      self.dependencyNames = dependenciesNames
    }
  }

  internal let fileDescriptorDataByFilename: [String: FileDescriptorProtoData]
  internal let serviceNames: [String]

  public init(fileDescriptor: [Google_Protobuf_FileDescriptorProto]) throws {
    var fileDescriptorDataAux: [String: FileDescriptorProtoData] = [:]
    var servicesAux: [String] = []

    do {
      for fileDescriptorProto in fileDescriptor {
        let protoDataObj = FileDescriptorProtoData(
          serializedFileDescriptorProto: try fileDescriptorProto.serializedData(),
          dependenciesNames: fileDescriptorProto.dependency
        )
        fileDescriptorDataAux[fileDescriptorProto.name] = protoDataObj
        servicesAux.append(contentsOf: fileDescriptorProto.service.map { $0.name })
      }
    } catch {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "One of the provided file descriptor protos is invalid."
      )
    }

    self.fileDescriptorDataByFilename = fileDescriptorDataAux
    self.serviceNames = servicesAux
  }

  public func getSerializedFileDescriptorProtos(fileName: String) throws -> [Data] {
    var toVisit = Deque<String>()
    var visited = Set<String>()
    var serializedFileDescriptorProtos: [Data] = []
    toVisit.append(fileName)

    while !toVisit.isEmpty {
      let currentFileName = toVisit.popFirst()
      if let protoData = self.fileDescriptorDataByFilename[currentFileName!] {
        let serializedFileDescriptorProto = protoData.serializedFileDescriptorProto
        if !protoData.dependencyNames.isEmpty {
          toVisit
            .append(
              contentsOf: protoData.dependencyNames
                .filter { name in
                  return !visited.contains(name)
                }
            )
        }
        serializedFileDescriptorProtos.append(serializedFileDescriptorProto)
      } else {
        throw GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      }
      visited.insert(currentFileName!)
    }
    return serializedFileDescriptorProtos
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class ReflectionService: Reflection_ServerReflectionAsyncProvider {
  private let protoRegistry: ReflectionServiceData

  public init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto]) throws {
    self.protoRegistry = try ReflectionServiceData(
      fileDescriptor: fileDescriptorProtos
    )
  }

  internal func findFileByFileName(
    fileName: String,
    request: Reflection_ServerReflectionRequest
  ) throws -> Reflection_ServerReflectionResponse {
    var fileDescriptorResponse = Reflection_FileDescriptorResponse()
    fileDescriptorResponse.fileDescriptorProto = try self.protoRegistry
      .getSerializedFileDescriptorProtos(fileName: fileName)
    return Reflection_ServerReflectionResponse(
      request: request,
      fileDescriptorResponse: fileDescriptorResponse
    )
  }

  internal func getServicesNames(
    request: Reflection_ServerReflectionRequest
  ) throws -> Reflection_ServerReflectionResponse {
    var listServicesResponse = Reflection_ListServiceResponse()
    listServicesResponse.service = self.protoRegistry.serviceNames.map({ serviceName in
      Reflection_ServiceResponse.with {
        $0.name = serviceName
      }
    })
    return Reflection_ServerReflectionResponse(
      request: request,
      listServicesResponse: listServicesResponse
    )
  }

  public func serverReflectionInfo(
    requestStream: GRPCAsyncRequestStream<Reflection_ServerReflectionRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Reflection_ServerReflectionResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await request in requestStream {
      switch request.messageRequest {
      case let .fileByFilename(fileName):
        let response = try self.findFileByFileName(
          fileName: fileName,
          request: request
        )
        try await responseStream.send(response)

      case .listServices:
        let response = try self.getServicesNames(request: request)
        try await responseStream.send(response)

      default:
        throw GRPCStatus(code: .unimplemented)
      }
    }
  }
}

extension Reflection_ServerReflectionResponse {
  init(
    request: Reflection_ServerReflectionRequest,
    fileDescriptorResponse: Reflection_FileDescriptorResponse
  ) {
    self = .with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.fileDescriptorResponse = fileDescriptorResponse
    }
  }

  init(
    request: Reflection_ServerReflectionRequest,
    listServicesResponse: Reflection_ListServiceResponse
  ) {
    self = .with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.listServicesResponse = listServicesResponse
    }
  }
}
