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
import XCTest

@testable import GRPCReflectionService

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class ReflectionServiceIntegrationTests: GRPCTestCase {
  private var server: Server?
  private var channel: GRPCChannel?
  private let protos: [Google_Protobuf_FileDescriptorProto] = makeProtosWithDependencies()
  private let independentProto: Google_Protobuf_FileDescriptorProto = generateFileDescriptorProto(
    fileName: "independentBar",
    suffix: "5"
  )
  private let versions: [ReflectionService.Version] = [.v1, .v1Alpha]

  private func setUpServerAndChannel(version: ReflectionService.Version) throws {
    let reflectionServiceProvider = try ReflectionService(
      fileDescriptorProtos: self.protos + [self.independentProto],
      version: version
    )

    let server = try Server.insecure(group: MultiThreadedEventLoopGroup.singleton)
      .withServiceProviders([reflectionServiceProvider])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
    self.server = server

    let channel = try GRPCChannelPool.with(
      target: .hostAndPort("127.0.0.1", server.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: MultiThreadedEventLoopGroup.singleton
    ) {
      $0.backgroundActivityLogger = self.clientLogger
    }

    self.channel = channel
  }

  override func tearDown() {
    if let channel = self.channel {
      XCTAssertNoThrow(try channel.close().wait())
    }
    if let server = self.server {
      XCTAssertNoThrow(try server.close().wait())
    }

    super.tearDown()
  }

  private func getServerReflectionResponse(
    for request: Grpc_Reflection_V1_ServerReflectionRequest,
    version: ReflectionService.Version
  ) async throws -> Grpc_Reflection_V1_ServerReflectionResponse? {
    let response: Grpc_Reflection_V1_ServerReflectionResponse?
    switch version {
    case .v1:
      let client = Grpc_Reflection_V1_ServerReflectionAsyncClient(channel: self.channel!)
      let serviceReflectionInfo = client.makeServerReflectionInfoCall()
      try await serviceReflectionInfo.requestStream.send(request)
      serviceReflectionInfo.requestStream.finish()
      var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
      response = try await iterator.next()
    case .v1Alpha:
      let client = Grpc_Reflection_V1alpha_ServerReflectionAsyncClient(channel: self.channel!)
      let serviceReflectionInfo = client.makeServerReflectionInfoCall()
      try await serviceReflectionInfo.requestStream.send(
        Grpc_Reflection_V1alpha_ServerReflectionRequest(request)
      )
      serviceReflectionInfo.requestStream.finish()
      var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
      response = try await iterator.next().map {
        Grpc_Reflection_V1_ServerReflectionResponse($0)
      }
    default:
      return nil
    }
    return response
  }

  private func forEachVersion(
    _ body: (GRPCChannel?, ReflectionService.Version) async throws -> Void
  ) async throws {
    for version in self.versions {
      try setUpServerAndChannel(version: version)
      let result: Result<Void, Error>
      do {
        try await body(self.channel, version)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      try result.get()
      try await self.tearDown()
    }
  }

  func testFileByFileName() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileByFilename = "bar1.proto"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")

      // response can't be nil as we just checked it.
      let receivedFileDescriptorProto =
        try Google_Protobuf_FileDescriptorProto(
          serializedData: (message.fileDescriptorResponse
            .fileDescriptorProto[0])
        )

      XCTAssertEqual(receivedFileDescriptorProto.name, "bar1.proto")
      XCTAssertEqual(receivedFileDescriptorProto.service.count, 1)

      let service = try XCTUnwrap(
        receivedFileDescriptorProto.service.first,
        "The received file descriptor proto doesn't have any services."
      )
      let method = try XCTUnwrap(
        service.method.first,
        "The service of the received file descriptor proto doesn't have any methods."
      )
      XCTAssertEqual(method.name, "testMethod1")
      XCTAssertEqual(message.fileDescriptorResponse.fileDescriptorProto.count, 4)
    }
  }

  func testListServices() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.listServices = "services"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      let receivedServices = message.listServicesResponse.service.map { $0.name }.sorted()
      let servicesNames = (self.protos + [self.independentProto]).flatMap {
        $0.qualifiedServiceNames
      }
      .sorted()

      XCTAssertEqual(receivedServices, servicesNames)
    }
  }

  func testFileBySymbol() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileContainingSymbol = "packagebar1.enumType1"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      let receivedData: [Google_Protobuf_FileDescriptorProto]
      do {
        receivedData = try message.fileDescriptorResponse.fileDescriptorProto.map {
          try Google_Protobuf_FileDescriptorProto(serializedData: $0)
        }
      } catch {
        return XCTFail("Could not serialize data received as a message.")
      }

      let fileToFind = self.protos[0]
      let dependentProtos = self.protos[1...]
      for fileDescriptorProto in receivedData {
        if fileDescriptorProto == fileToFind {
          XCTAssert(
            fileDescriptorProto.enumType.names.contains("enumType1"),
            """
            The response doesn't contain the serialized file descriptor proto \
            containing the \"packagebar1.enumType1\" symbol.
            """
          )
        } else {
          XCTAssert(
            dependentProtos.contains(fileDescriptorProto),
            """
            The \(fileDescriptorProto.name) is not a dependency of the \
            proto file containing the \"packagebar1.enumType1\" symbol.
            """
          )
        }
      }
    }
  }

  func testFileByExtension() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileContainingExtension = .with {
          $0.containingType = "packagebar1.inputMessage1"
          $0.extensionNumber = 2
        }
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      let receivedData: [Google_Protobuf_FileDescriptorProto]
      do {
        receivedData = try message.fileDescriptorResponse.fileDescriptorProto.map {
          try Google_Protobuf_FileDescriptorProto(serializedData: $0)
        }
      } catch {
        return XCTFail("Could not serialize data received as a message.")
      }

      let fileToFind = self.protos[0]
      let dependentProtos = self.protos[1...]
      var receivedProtoContainingExtension = 0
      var dependenciesCount = 0
      for fileDescriptorProto in receivedData {
        if fileDescriptorProto == fileToFind {
          receivedProtoContainingExtension += 1
          XCTAssert(
            fileDescriptorProto.extension.map { $0.name }.contains(
              "extension.packagebar1.inputMessage1-2"
            ),
            """
            The response doesn't contain the serialized file descriptor proto \
            containing the \"extensioninputMessage1-2\" extension.
            """
          )
        } else {
          dependenciesCount += 1
          XCTAssert(
            dependentProtos.contains(fileDescriptorProto),
            """
            The \(fileDescriptorProto.name) is not a dependency of the \
            proto file containing the \"extensioninputMessage1-2\" extension.
            """
          )
        }
      }
      XCTAssertEqual(
        receivedProtoContainingExtension,
        1,
        "The file descriptor proto of the proto containing the extension was not received."
      )
      XCTAssertEqual(dependenciesCount, 3)
    }
  }

  func testAllExtensionNumbersOfType() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.allExtensionNumbersOfType = "packagebar2.inputMessage2"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      XCTAssertEqual(message.allExtensionNumbersResponse.baseTypeName, "packagebar2.inputMessage2")
      XCTAssertEqual(message.allExtensionNumbersResponse.extensionNumber, [1, 2, 3, 4, 5])
    }
  }

  func testErrorResponseFileByFileNameRequest() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileByFilename = "invalidFileName.proto"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      XCTAssertEqual(message.errorResponse.errorCode, Int32(GRPCStatus.Code.notFound.rawValue))
      XCTAssertEqual(
        message.errorResponse.errorMessage,
        "The provided file or a dependency of the provided file could not be found."
      )
    }
  }

  func testErrorResponseFileBySymbolRequest() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileContainingSymbol = "packagebar1.invalidEnumType1"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      XCTAssertEqual(message.errorResponse.errorCode, Int32(GRPCStatus.Code.notFound.rawValue))
      XCTAssertEqual(message.errorResponse.errorMessage, "The provided symbol could not be found.")
    }
  }

  func testErrorResponseFileByExtensionRequest() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.fileContainingExtension = .with {
          $0.containingType = "packagebar1.invalidInputMessage1"
          $0.extensionNumber = 2
        }
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      XCTAssertEqual(message.errorResponse.errorCode, Int32(GRPCStatus.Code.notFound.rawValue))
      XCTAssertEqual(
        message.errorResponse.errorMessage,
        "The provided extension could not be found."
      )
    }
  }

  func testErrorResponseAllExtensionNumbersOfTypeRequest() async throws {
    try await self.forEachVersion { channel, version in
      let request = Grpc_Reflection_V1_ServerReflectionRequest.with {
        $0.host = "127.0.0.1"
        $0.allExtensionNumbersOfType = "packagebar2.invalidInputMessage2"
      }
      let response = try await self.getServerReflectionResponse(for: request, version: version)
      let message = try XCTUnwrap(response, "Could not get a response message.")
      XCTAssertEqual(
        message.errorResponse.errorCode,
        Int32(GRPCStatus.Code.invalidArgument.rawValue)
      )
      XCTAssertEqual(message.errorResponse.errorMessage, "The provided type is invalid.")
    }
  }
}
