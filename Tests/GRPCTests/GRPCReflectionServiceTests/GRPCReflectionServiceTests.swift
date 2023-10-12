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

final class GRPCReflectionServiceTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup?
  private var server: Server?
  private var channel: GRPCChannel?

  private func generateProto(name: String, id: Int) -> Google_Protobuf_FileDescriptorProto {
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
      $0.messageType = [inputMessage, outputMessage]
    }

    return fileDescriptorProto
  }

  /// Creates the dependencies of the proto used in the testing context.
  private func makeProtosWithDependencies() -> [Google_Protobuf_FileDescriptorProto] {
    var fileDependencies: [Google_Protobuf_FileDescriptorProto] = []
    for id in 1 ... 4 {
      let fileDescriptorProto = self.generateProto(name: "bar", id: id)
      if id != 1 {
        // Dependency of the first dependency.
        fileDependencies[0].dependency.append(fileDescriptorProto.name)
      }
      fileDependencies.append(fileDescriptorProto)
    }
    return fileDependencies
  }

  private func makeProtosWithComplexDependencies() -> [Google_Protobuf_FileDescriptorProto] {
    var protos: [Google_Protobuf_FileDescriptorProto] = []
    protos.append(self.generateProto(name: "foo", id: 0))
    for id in 1 ... 10 {
      let fileDescriptorProtoA = self.generateProto(name: "fooA", id: id)
      let fileDescriptorProtoB = self.generateProto(name: "fooB", id: id)
      let parent = protos.count > 1 ? protos.count - Int.random(in: 1 ..< 3) : protos.count - 1
      protos[parent].dependency.append(fileDescriptorProtoA.name)
      protos[parent].dependency.append(fileDescriptorProtoB.name)
      protos.append(fileDescriptorProtoA)
      protos.append(fileDescriptorProtoB)
    }
    return protos
  }

  private func getServicesNamesFromProtos(
    protos: [Google_Protobuf_FileDescriptorProto]
  ) -> [String] {
    return protos.serviceNames
  }

  private func setUpServerAndChannel() throws {
    let reflectionServiceProvider = try ReflectionService(
      fileDescriptors: self.makeProtosWithDependencies()
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

  func testFileByFileName() async throws {
    try self.setUpServerAndChannel()
    let client = Reflection_ServerReflectionAsyncClient(channel: self.channel!)
    let serviceReflectionInfo = client.makeServerReflectionInfoCall()
    try await serviceReflectionInfo.requestStream.send(
      .with {
        $0.host = "127.0.0.1"
        $0.fileByFilename = "bar1.proto"
      }
    )
    serviceReflectionInfo.requestStream.finish()

    var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
    guard let message = try await iterator.next() else {
      return XCTFail("Could not get a response message.")
    }

    let receivedFileDescriptorProto =
      try Google_Protobuf_FileDescriptorProto(
        serializedData: (message.fileDescriptorResponse
          .fileDescriptorProto[0])
      )

    XCTAssertEqual(receivedFileDescriptorProto.name, "bar1.proto")
    XCTAssertEqual(receivedFileDescriptorProto.service.count, 1)

    guard let service = receivedFileDescriptorProto.service.first else {
      return XCTFail("The received file descriptor proto doesn't have any services.")
    }
    guard let method = service.method.first else {
      return XCTFail("The service of the received file descriptor proto doesn't have any methods.")
    }
    XCTAssertEqual(method.name, "testMethod1")
    XCTAssertEqual(message.fileDescriptorResponse.fileDescriptorProto.count, 4)
  }

  func testListServices() async throws {
    try self.setUpServerAndChannel()
    let client = Reflection_ServerReflectionAsyncClient(channel: self.channel!)
    let serviceReflectionInfo = client.makeServerReflectionInfoCall()

    try await serviceReflectionInfo.requestStream.send(
      .with {
        $0.host = "127.0.0.1"
        $0.listServices = "services"
      }
    )

    serviceReflectionInfo.requestStream.finish()
    var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
    guard let message = try await iterator.next() else {
      return XCTFail("Could not get a response message.")
    }

    let receivedServices = message.listServicesResponse.service.map { $0.name }.sorted()
    let servicesNames = self.getServicesNamesFromProtos(
      protos: self.makeProtosWithDependencies()
    ).sorted()

    XCTAssertEqual(receivedServices, servicesNames)
  }

  func testReflectionServiceDataFileDescriptorDataByFilename() throws {
    var protos = self.makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)

    let registryFileDescriptorData = registry.fileDescriptorDataByFilename

    for (fileName, protoData) in registryFileDescriptorData {
      let serializedFiledescriptorData = protoData.serializedFileDescriptorProto
      let dependencyFileNames = protoData.dependencyFileNames

      guard let index = protos.firstIndex(where: { $0.name == fileName }) else {
        return XCTFail(
          """
          Could not find the file descriptor proto of \(fileName) \
          in the original file descriptor protos list.
          """
        )
      }

      let originalProto = protos[index]
      XCTAssertEqual(originalProto.name, fileName)
      XCTAssertEqual(try originalProto.serializedData(), serializedFiledescriptorData)
      XCTAssertEqual(originalProto.dependency, dependencyFileNames)

      protos.remove(at: index)
    }
    XCTAssert(protos.isEmpty)
  }

  func testReflectionServiceServicesNames() throws {
    let protos = self.makeProtosWithDependencies()
    let servicesNames = self.getServicesNamesFromProtos(protos: protos).sorted()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let registryServices = registry.serviceNames.sorted()
    XCTAssertEqual(registryServices, servicesNames)
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFile() throws {
    var protos = self.makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtos =
      try registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")
    let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
      try Google_Protobuf_FileDescriptorProto(serializedData: $0)
    }
    // Tests that the functions returns all the transitive dependencies, with their services and
    // methods, together with the initial proto, as serialized data.
    XCTAssertEqual(fileDescriptorProtos.count, 4)
    for fileDescriptorProto in fileDescriptorProtos {
      guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
        return XCTFail(
          """
          Could not find the file descriptor proto of \(fileDescriptorProto.name) \
          in the original file descriptor protos list.
          """
        )
      }

      for service in fileDescriptorProto.service {
        guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
          return XCTFail(
            """
            Could not find the \(service.name) in the service \
            list of the \(fileDescriptorProto.name) file descriptor proto.
            """
          )
        }

        let originalMethods = protos[protoIndex].service[serviceIndex].method
        for method in service.method {
          XCTAssert(originalMethods.contains(method))
        }

        for messageType in fileDescriptorProto.messageType {
          XCTAssert(protos[protoIndex].messageType.contains(messageType))
        }
      }

      protos.removeAll { $0 == fileDescriptorProto }
    }
    XCTAssert(protos.isEmpty)
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileComplexDependencyGraph() throws {
    var protos = self.makeProtosWithComplexDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtos =
      try registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "foo0.proto")
    let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
      try Google_Protobuf_FileDescriptorProto(serializedData: $0)
    }
    // Tests that the functions returns all the tranzitive dependencies, with their services and
    // methods, together with the initial proto, as serialized data.
    XCTAssertEqual(fileDescriptorProtos.count, 21)
    for fileDescriptorProto in fileDescriptorProtos {
      guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
        return XCTFail(
          """
          Could not find the file descriptor proto of \(fileDescriptorProto.name) \
          in the original file descriptor protos list.
          """
        )
      }

      for service in fileDescriptorProto.service {
        guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
          return XCTFail(
            """
            Could not find the \(service.name) in the service \
            list of the \(fileDescriptorProto.name) file descriptor proto.
            """
          )
        }

        let originalMethods = protos[protoIndex].service[serviceIndex].method
        for method in service.method {
          XCTAssert(originalMethods.contains(method))
        }

        for messageType in fileDescriptorProto.messageType {
          XCTAssert(protos[protoIndex].messageType.contains(messageType))
        }
      }

      protos.removeAll { $0 == fileDescriptorProto }
    }
    XCTAssert(protos.isEmpty)
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileDependencyLoops() throws {
    var protos = self.makeProtosWithDependencies()
    // Making dependencies of the "bar1.proto" to depend on "bar1.proto".
    protos[1].dependency.append("bar1.proto")
    protos[2].dependency.append("bar1.proto")
    protos[3].dependency.append("bar1.proto")
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtos =
      try registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")
    let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
      try Google_Protobuf_FileDescriptorProto(serializedData: $0)
    }
    // Test that we get only 4 serialized File Descriptor Protos as response.
    XCTAssertEqual(fileDescriptorProtos.count, 4)
    for fileDescriptorProto in fileDescriptorProtos {
      guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
        return XCTFail(
          """
          Could not find the file descriptor proto of \(fileDescriptorProto.name) \
          in the original file descriptor protos list.
          """
        )
      }

      for service in fileDescriptorProto.service {
        guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
          return XCTFail(
            """
            Could not find the \(service.name) in the service \
            list of the \(fileDescriptorProto.name) file descriptor proto.
            """
          )
        }

        let originalMethods = protos[protoIndex].service[serviceIndex].method
        for method in service.method {
          XCTAssert(originalMethods.contains(method))
        }

        for messageType in fileDescriptorProto.messageType {
          XCTAssert(protos[protoIndex].messageType.contains(messageType))
        }
      }

      protos.removeAll { $0 == fileDescriptorProto }
    }
    XCTAssert(protos.isEmpty)
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileInvalidFile() throws {
    let protos = self.makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    XCTAssertThrowsError(
      try registry.serialisedFileDescriptorProtosForDependenciesOfFile(named: "invalid.proto")
    ) { error in
      XCTAssertEqual(
        error as? GRPCStatus,
        GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      )
    }
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileDependencyNotProto() throws {
    var protos = self.makeProtosWithDependencies()
    protos[0].dependency.append("invalidDependency")
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    XCTAssertThrowsError(
      try registry.serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")
    ) { error in
      XCTAssertEqual(
        error as? GRPCStatus,
        GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      )
    }
  }
}

extension Sequence where Element == Google_Protobuf_FileDescriptorProto {
  var serviceNames: [String] {
    self.flatMap { $0.service.map { $0.name } }
  }
}
