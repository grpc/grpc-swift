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
  private struct ExtensionDescriptor: Sendable, Hashable {
    internal let extendeeTypeName: String
    internal let fieldNumber: Int32
  }

  internal var fileDescriptorDataByFilename: [String: FileDescriptorProtoData]
  internal var serviceNames: [String]
  internal var fileNameBySymbol: [String: String]

  // Stores the file names for each extension identified by an ExtensionDescriptor object.
  private var fileNameByExtensionDescriptor: [ExtensionDescriptor: String]
  // Stores the field numbers for each type that has extensions.
  private var fieldNumbersByType: [String: [Int32]]

  internal init(fileDescriptors: [Google_Protobuf_FileDescriptorProto]) throws {
    self.serviceNames = []
    self.fileDescriptorDataByFilename = [:]
    self.fileNameBySymbol = [:]
    self.fileNameByExtensionDescriptor = [:]
    self.fieldNumbersByType = [:]

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

      // Populating the <symbol, file name> dictionary.
      for qualifiedSybolName in fileDescriptorProto.qualifiedSymbolNames {
        let oldValue = self.fileNameBySymbol.updateValue(
          fileDescriptorProto.name,
          forKey: qualifiedSybolName
        )
        if let oldValue = oldValue {
          throw GRPCStatus(
            code: .alreadyExists,
            message:
              "The \(qualifiedSybolName) symbol from \(fileDescriptorProto.name) already exists in \(oldValue)."
          )
        }
      }

      for typeName in fileDescriptorProto.qualifiedMessageTypes {
        self.fieldNumbersByType[typeName] = []
      }

      // Populating the <extension descriptor, file name> dictionary and the <typeName, [FieldNumber]> one.
      for `extension` in fileDescriptorProto.extension {
        let typeName = String(`extension`.extendee.drop(while: { $0 == "." }))
        let extensionDescriptor = ExtensionDescriptor(
          extendeeTypeName: typeName,
          fieldNumber: `extension`.number
        )
        let oldFileName = self.fileNameByExtensionDescriptor.updateValue(
          fileDescriptorProto.name,
          forKey: extensionDescriptor
        )
        if let oldFileName = oldFileName {
          throw GRPCStatus(
            code: .alreadyExists,
            message:
              """
              The extension of the \(extensionDescriptor.extendeeTypeName) type with the field number equal to \
              \(extensionDescriptor.fieldNumber) from \(fileDescriptorProto.name) already exists in \(oldFileName).
              """
          )
        }
        self.fieldNumbersByType[typeName, default: []].append(`extension`.number)
      }
    }
  }

  internal func serialisedFileDescriptorProtosForDependenciesOfFile(
    named fileName: String
  ) -> Result<[Data], GRPCStatus> {
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
        return .failure(
          GRPCStatus(
            code: .notFound,
            message: "The provided file or a dependency of the provided file could not be found."
          )
        )
      }
      visited.insert(currentFileName)
    }
    return .success(serializedFileDescriptorProtos)
  }

  internal func nameOfFileContainingSymbol(named symbolName: String) -> Result<String, GRPCStatus> {
    guard let fileName = self.fileNameBySymbol[symbolName] else {
      return .failure(
        GRPCStatus(
          code: .notFound,
          message: "The provided symbol could not be found."
        )
      )
    }
    return .success(fileName)
  }

  internal func nameOfFileContainingExtension(
    extendeeName: String,
    fieldNumber number: Int32
  ) -> Result<String, GRPCStatus> {
    let key = ExtensionDescriptor(extendeeTypeName: extendeeName, fieldNumber: number)
    guard let fileName = self.fileNameByExtensionDescriptor[key] else {
      return .failure(
        GRPCStatus(
          code: .notFound,
          message: "The provided extension could not be found."
        )
      )
    }
    return .success(fileName)
  }

  // Returns an empty array if the type has no extensions.
  internal func extensionsFieldNumbersOfType(
    named typeName: String
  ) -> Result<[Int32], GRPCStatus> {
    guard let fieldNumbers = self.fieldNumbersByType[typeName] else {
      return .failure(
        GRPCStatus(
          code: .invalidArgument,
          message: "The provided type is invalid."
        )
      )
    }
    return .success(fieldNumbers)
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

  internal func _findFileByFileName(
    _ fileName: String
  ) -> Result<Reflection_ServerReflectionResponse.OneOf_MessageResponse, GRPCStatus> {
    return self.protoRegistry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: fileName)
      .map { fileDescriptorProtos in
        Reflection_ServerReflectionResponse.OneOf_MessageResponse.fileDescriptorResponse(
          .with {
            $0.fileDescriptorProto = fileDescriptorProtos
          }
        )
      }
  }

  internal func findFileByFileName(
    _ fileName: String,
    request: Reflection_ServerReflectionRequest
  ) -> Reflection_ServerReflectionResponse {
    let result = self._findFileByFileName(fileName)
    return result.makeResponse(request: request)
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
      messageResponse: .listServicesResponse(listServicesResponse)
    )
  }

  internal func findFileBySymbol(
    _ symbolName: String,
    request: Reflection_ServerReflectionRequest
  ) -> Reflection_ServerReflectionResponse {
    let result = self.protoRegistry.nameOfFileContainingSymbol(
      named: symbolName
    ).flatMap {
      self._findFileByFileName($0)
    }
    return result.makeResponse(request: request)
  }

  internal func findFileByExtension(
    extensionRequest: Reflection_ExtensionRequest,
    request: Reflection_ServerReflectionRequest
  ) -> Reflection_ServerReflectionResponse {
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
    request: Reflection_ServerReflectionRequest
  ) -> Reflection_ServerReflectionResponse {
    let result = self.protoRegistry.extensionsFieldNumbersOfType(
      named: typeName
    ).map { fieldNumbers in
      Reflection_ServerReflectionResponse.OneOf_MessageResponse.allExtensionNumbersResponse(
        Reflection_ExtensionNumberResponse.with {
          $0.baseTypeName = typeName
          $0.extensionNumber = fieldNumbers
        }
      )
    }
    return result.makeResponse(request: request)
  }

  internal func serverReflectionInfo(
    requestStream: GRPCAsyncRequestStream<Reflection_ServerReflectionRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Reflection_ServerReflectionResponse>,
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
        let response = Reflection_ServerReflectionResponse(
          request: request,
          messageResponse: .errorResponse(
            Reflection_ErrorResponse.with {
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

extension Reflection_ServerReflectionResponse {
  init(
    request: Reflection_ServerReflectionRequest,
    messageResponse: Reflection_ServerReflectionResponse.OneOf_MessageResponse
  ) {
    self = .with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.messageResponse = messageResponse
    }
  }
}

extension Google_Protobuf_FileDescriptorProto {
  var qualifiedServiceAndMethodNames: [String] {
    var names: [String] = []

    for service in self.service {
      names.append(self.package + "." + service.name)
      names.append(
        contentsOf: service.method
          .map { self.package + "." + service.name + "." + $0.name }
      )
    }
    return names
  }

  var qualifiedMessageTypes: [String] {
    return self.messageType.map {
      self.package + "." + $0.name
    }
  }

  var qualifiedEnumTypes: [String] {
    return self.enumType.map {
      self.package + "." + $0.name
    }
  }

  var qualifiedSymbolNames: [String] {
    var names = self.qualifiedServiceAndMethodNames
    names.append(contentsOf: self.qualifiedMessageTypes)
    names.append(contentsOf: self.qualifiedEnumTypes)
    return names
  }
}

extension Result<Reflection_ServerReflectionResponse.OneOf_MessageResponse, GRPCStatus> {
  func recover() -> Result<Reflection_ServerReflectionResponse.OneOf_MessageResponse, Never> {
    self.flatMapError { status in
      let error = Reflection_ErrorResponse.with {
        $0.errorCode = Int32(status.code.rawValue)
        $0.errorMessage = status.message ?? ""
      }
      return .success(.errorResponse(error))
    }
  }

  func makeResponse(
    request: Reflection_ServerReflectionRequest
  ) -> Reflection_ServerReflectionResponse {
    let result = self.recover().attachRequest(request)
    // Safe to '!' as the failure type is 'Never'.
    return try! result.get()
  }
}

extension Result where Success == Reflection_ServerReflectionResponse.OneOf_MessageResponse {
  func attachRequest(
    _ request: Reflection_ServerReflectionRequest
  ) -> Result<Reflection_ServerReflectionResponse, Failure> {
    self.map { message in
      Reflection_ServerReflectionResponse(request: request, messageResponse: message)
    }
  }
}
