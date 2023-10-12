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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class ReflectionService: CallHandlerProvider, Sendable {
  private let reflectionService: ReflectionServiceProvider
  public var serviceName: Substring {
    self.reflectionService.serviceName
  }

  public init(fileDescriptors: [Google_Protobuf_FileDescriptorProto]) throws {
    self.reflectionService = try ReflectionServiceProvider(fileDescriptorProtos: fileDescriptors)
  }

  public func handle(
    method name: Substring,
    context: GRPC.CallHandlerContext
  ) -> GRPC.GRPCServerHandlerProtocol? {
    self.reflectionService.handle(method: name, context: context)
  }
}

internal struct ReflectionServiceData: Sendable {
  internal struct FileDescriptorProtoData: Sendable {
    internal var serializedFileDescriptorProto: Data
    internal var dependencyFileNames: [String]
  }

  internal var fileDescriptorDataByFilename: [String: FileDescriptorProtoData]
  internal var serviceNames: [String]

  internal init(fileDescriptors: [Google_Protobuf_FileDescriptorProto]) throws {
    self.serviceNames = []
    self.fileDescriptorDataByFilename = [:]
    for fileDescriptorProto in fileDescriptors {
      let serializedFileDescriptorProto: Data
      do {
        serializedFileDescriptorProto = try fileDescriptorProto.serializedData()
      } catch {
        throw GRPCStatus(
          code: .invalidArgument,
          message:
            "The \(fileDescriptorProto.name) could not be serialized."
        )
      }
      let protoData = FileDescriptorProtoData(
        serializedFileDescriptorProto: serializedFileDescriptorProto,
        dependencyFileNames: fileDescriptorProto.dependency
      )
      self.fileDescriptorDataByFilename[fileDescriptorProto.name] = protoData
      self.serviceNames.append(contentsOf: fileDescriptorProto.service.map { $0.name })
    }
  }

  internal func serialisedFileDescriptorProtosForDependenciesOfFile(
    named fileName: String
  ) throws -> [Data] {
    var toVisit = Deque<String>()
    var visited = Set<String>()
    var serializedFileDescriptorProtos: [Data] = []
    toVisit.append(fileName)

    while let currentFileName = toVisit.popFirst() {
      if let protoData = self.fileDescriptorDataByFilename[currentFileName] {
        toVisit.append(
          contentsOf: protoData.dependencyFileNames
            .filter { name in
              return !visited.contains(name)
            }
        )

        let serializedFileDescriptorProto = protoData.serializedFileDescriptorProto
        serializedFileDescriptorProtos.append(serializedFileDescriptorProto)
      } else {
        throw GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      }
      visited.insert(currentFileName)
    }
    return serializedFileDescriptorProtos
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class ReflectionServiceProvider: Reflection_ServerReflectionAsyncProvider {
  private let protoRegistry: ReflectionServiceData

  internal init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto]) throws {
    self.protoRegistry = try ReflectionServiceData(
      fileDescriptors: fileDescriptorProtos
    )
  }

  internal func findFileByFileName(
    _ fileName: String,
    request: Reflection_ServerReflectionRequest
  ) throws -> Reflection_ServerReflectionResponse {
    return Reflection_ServerReflectionResponse(
      request: request,
      fileDescriptorResponse: try .with {
        $0.fileDescriptorProto = try self.protoRegistry
          .serialisedFileDescriptorProtosForDependenciesOfFile(named: fileName)
      }
    )
  }

  internal func getServicesNames(
    request: Reflection_ServerReflectionRequest
  ) throws -> Reflection_ServerReflectionResponse {
    var listServicesResponse = Reflection_ListServiceResponse()
    listServicesResponse.service = self.protoRegistry.serviceNames.map { serviceName in
      Reflection_ServiceResponse.with {
        $0.name = serviceName
      }
    }
    return Reflection_ServerReflectionResponse(
      request: request,
      listServicesResponse: listServicesResponse
    )
  }

  internal func serverReflectionInfo(
    requestStream: GRPCAsyncRequestStream<Reflection_ServerReflectionRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Reflection_ServerReflectionResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await request in requestStream {
      switch request.messageRequest {
      case let .fileByFilename(fileName):
        let response = try self.findFileByFileName(
          fileName,
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
