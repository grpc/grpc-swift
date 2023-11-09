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
  private let provider: Provider

  public var serviceName: Substring {
    switch self.provider {
    case .v1(let provider):
      return provider.serviceName
    case .v1Alpha(let provider):
      return provider.serviceName
    }
  }

  /// Creates a `ReflectionService` by loading serialized reflection data created by `protoc-gen-grpc-swift`.
  ///
  /// You can generate serialized reflection data using the `protoc-gen-grpc-swift` plugin for `protoc` by
  /// setting the `ReflectionData` option  to `True`. The paths provided should be absolute or relative to the
  /// current working directory.
  ///
  /// - Parameter filePaths: The paths to files containing serialized reflection data.
  /// - Parameter version: The version of the reflection service to create.
  ///
  /// - Throws: When a file can't be read from disk or parsed.
  public init(serializedFileDescriptorProtoFilePaths filePaths: [String], version: Version) throws {
    let fileDescriptorProtos = try ReflectionService.readSerializedFileDescriptorProtos(
      atPaths: filePaths
    )
    switch version.wrapped {
    case .v1:
      self.provider = .v1(
        try ReflectionServiceProviderV1(fileDescriptorProtos: fileDescriptorProtos)
      )
    case .v1Alpha:
      self.provider = .v1Alpha(
        try ReflectionServiceProviderV1Alpha(fileDescriptorProtos: fileDescriptorProtos)
      )
    }
  }

  public init(fileDescriptorProtos: [Google_Protobuf_FileDescriptorProto], version: Version) throws
  {
    switch version.wrapped {
    case .v1:
      self.provider = .v1(
        try ReflectionServiceProviderV1(fileDescriptorProtos: fileDescriptorProtos)
      )
    case .v1Alpha:
      self.provider = .v1Alpha(
        try ReflectionServiceProviderV1Alpha(fileDescriptorProtos: fileDescriptorProtos)
      )
    }
  }

  public func handle(
    method name: Substring,
    context: GRPC.CallHandlerContext
  ) -> GRPC.GRPCServerHandlerProtocol? {
    switch self.provider {
    case .v1(let reflectionV1Provider):
      return reflectionV1Provider.handle(method: name, context: context)
    case .v1Alpha(let reflectionV1AlphaProvider):
      return reflectionV1AlphaProvider.handle(method: name, context: context)
    }
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
      self.serviceNames.append(
        contentsOf: fileDescriptorProto.service.map { fileDescriptorProto.package + "." + $0.name }
      )
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ReflectionService {
  /// The version of the reflection service.
  ///
  /// Depending in the version you are using, when creating the ReflectionService
  /// provide the corresponding `Version` variable (`v1` or `v1Alpha`).
  public struct Version: Sendable, Hashable {
    internal enum Wrapped {
      case v1
      case v1Alpha
    }
    var wrapped: Wrapped
    private init(_ wrapped: Wrapped) { self.wrapped = wrapped }

    /// The v1 version of reflection service: https://github.com/grpc/grpc/blob/master/src/proto/grpc/reflection/v1/reflection.proto.
    public static var v1: Self { Self(.v1) }
    /// The v1alpha version of reflection service: https://github.com/grpc/grpc/blob/master/src/proto/grpc/reflection/v1alpha/reflection.proto.
    public static var v1Alpha: Self { Self(.v1Alpha) }
  }

  private enum Provider {
    case v1(ReflectionServiceProviderV1)
    case v1Alpha(ReflectionServiceProviderV1Alpha)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ReflectionService {
  static func readSerializedFileDescriptorProto(
    atPath path: String
  ) throws -> Google_Protobuf_FileDescriptorProto {
    let fileURL: URL
    #if os(Linux)
    fileURL = URL(fileURLWithPath: path)
    #else
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
      fileURL = URL(filePath: path, directoryHint: .notDirectory)
    } else {
      fileURL = URL(fileURLWithPath: path)
    }
    #endif
    let binaryData = try Data(contentsOf: fileURL)
    guard let serializedData = Data(base64Encoded: binaryData) else {
      throw GRPCStatus(
        code: .invalidArgument,
        message:
          """
          The \(path) file contents could not be transformed \
          into serialized data representing a file descriptor proto.
          """
      )
    }
    return try Google_Protobuf_FileDescriptorProto(serializedData: serializedData)
  }

  static func readSerializedFileDescriptorProtos(
    atPaths paths: [String]
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    var fileDescriptorProtos = [Google_Protobuf_FileDescriptorProto]()
    fileDescriptorProtos.reserveCapacity(paths.count)
    for path in paths {
      try fileDescriptorProtos.append(readSerializedFileDescriptorProto(atPath: path))
    }
    return fileDescriptorProtos
  }
}
