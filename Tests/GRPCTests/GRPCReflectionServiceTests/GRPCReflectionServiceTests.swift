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

final class GRPCReflectionServiceTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup?
  private var server: Server?
  private var channel: GRPCChannel?

  private var fileDescriptorProto: Google_Protobuf_FileDescriptorProto? = nil
  private var protos: [Google_Protobuf_FileDescriptorProto] = []
  private var servicesNames: [String] = []

  /// Creates the dependencies of the proto used in the testing context.
  private func createDependencies() -> [String] {
    var fileDependencies: [String] = []
    for id in 1 ... 4 {
      let inputMessage = Google_Protobuf_DescriptorProto.with {
        $0.name = "inputMessage"
        $0.field = [Google_Protobuf_FieldDescriptorProto.with {
          $0.name = "inputField"
          $0.type = .bool
        }]
      }

      let outputMessage = Google_Protobuf_DescriptorProto.with {
        $0.name = "inputMessage"
        $0.field = [Google_Protobuf_FieldDescriptorProto.with {
          $0.name = "outputField"
          $0.type = .int32
        }]
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
      self.servicesNames.append("service" + String(id))
      let fileDescriptorProto = Google_Protobuf_FileDescriptorProto.with {
        $0.service = [serviceDescriptor]
        $0.name = "bar" + String(id) + ".proto"
        $0.messageType = [inputMessage, outputMessage]
      }
      self.protos.append(fileDescriptorProto)
      if (id == 4) {
        // Dependency of the first dependency.
        self.protos[0].dependency = [fileDescriptorProto.name]
      } else {
        fileDependencies.append(fileDescriptorProto.name)
      }
    }
    return fileDependencies
  }

  private func createFileDescriptorProto() {
    let method = Google_Protobuf_MethodDescriptorProto.with {
      $0.name = "testMethod0"
    }

    let servicedescriptor = Google_Protobuf_ServiceDescriptorProto.with {
      $0.method = [method]
      $0.name = "service0"
    }
    self.servicesNames.append("service0")
    let fileDescriptorProto = Google_Protobuf_FileDescriptorProto.with {
      $0.service = [servicedescriptor]
      $0.name = "bar.proto"
      $0.dependency = self.createDependencies()
    }
    self.protos.append(fileDescriptorProto)
    self.fileDescriptorProto = fileDescriptorProto
  }

  private func setUpServerAndChannel() throws {
    self.createFileDescriptorProto()
    let reflectionService = try ReflectionService(fileDescriptorProtos: self.protos)

    let server = try Server.insecure(group: MultiThreadedEventLoopGroup.singleton)
      .withServiceProviders([reflectionService])
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
    try await serviceReflectionInfo.requestStream.send(.with {
      $0.host = "127.0.0.1"
      $0.fileByFilename = "bar.proto"
    })
    serviceReflectionInfo.requestStream.finish()

    var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
    let message = try await iterator.next()
    let receivedFileDescriptorProto =
      try Google_Protobuf_FileDescriptorProto(serializedData: (
        message?.fileDescriptorResponse
          .fileDescriptorProto[0]
      )!)
    XCTAssertEqual(receivedFileDescriptorProto.name, self.fileDescriptorProto!.name)
    XCTAssertEqual(
      receivedFileDescriptorProto.service.count,
      self.fileDescriptorProto!.service.count
    )
    XCTAssertEqual(
      receivedFileDescriptorProto.service.first!.method.first!.name,
      self.fileDescriptorProto!.service.first!.method.first!.name
    )
    XCTAssertEqual(message?.fileDescriptorResponse.fileDescriptorProto.count, 5)
  }

  func testListServices() async throws {
    try self.setUpServerAndChannel()
    let client = Reflection_ServerReflectionAsyncClient(channel: self.channel!)
    let serviceReflectionInfo = client.makeServerReflectionInfoCall()
    try await serviceReflectionInfo.requestStream.send(.with {
      $0.host = "127.0.0.1"
      $0.listServices = "services"
    })
    serviceReflectionInfo.requestStream.finish()
    var iterator = serviceReflectionInfo.responseStream.makeAsyncIterator()
    let message = try await iterator.next()
    let receivedServices = message?.listServicesResponse.service.map { $0.name }
    XCTAssertEqual(receivedServices?.count, 5)
    for serviceName in receivedServices! {
      XCTAssertTrue(self.servicesNames.contains(serviceName))
    }
  }

  func testReflectionServiceData() throws {
    self.createFileDescriptorProto()
    do {
      let registry = try ReflectionServiceData(fileDescriptorProtos: self.protos)
      let registryFileDescriptorData = registry.getfileDescriptorData()
      let services = registry.getServices()

      for (fileName, protoData) in registryFileDescriptorData {
        let serializedFiledescriptorData = protoData.getSerializedFileDescriptorProto()
        let dependecies = protoData.getDependency()

        let originalIndex = self.protos.firstIndex(where: { $0.name == fileName })
        XCTAssertNotNil(originalIndex)

        let originalProto = self.protos[originalIndex!]
        XCTAssertEqual(originalProto.name, fileName)
        XCTAssertEqual(try originalProto.serializedData(), serializedFiledescriptorData)
        XCTAssertEqual(originalProto.dependency, dependecies)

        self.protos.remove(at: originalIndex!)
      }

      for serviceName in services {
        XCTAssert(self.servicesNames.contains(serviceName))
        self.servicesNames.removeAll { $0 == serviceName }
      }
    } catch {
      XCTFail(error.localizedDescription)
    }
  }

  func testGetSerializedFileDescriptorProtos() throws {
    self.createFileDescriptorProto()
    do {
      let registry = try ReflectionServiceData(fileDescriptorProtos: self.protos)
      let serializedFileDescriptorProtos = try registry
        .getSerializedFileDescriptorProtos(fileName: "bar.proto")
      let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
        try Google_Protobuf_FileDescriptorProto(serializedData: $0)
      }
      // Tests that the functions returns all the tranzitive dependencies, with their services and
      // methods, together with the initial proto, as serialized data.
      XCTAssertEqual(fileDescriptorProtos.count, 5)
      for fileDescriptorProto in fileDescriptorProtos {
        XCTAssert(self.protos.contains(fileDescriptorProto))
        let protoIndex = self.protos.firstIndex(of: fileDescriptorProto)
        for service in fileDescriptorProto.service {
          XCTAssert(self.protos[protoIndex!].service.contains(service))
          let serviceIndex = self.protos[protoIndex!].service.firstIndex(of: service)
          let originalMethods = self.protos[protoIndex!].service[serviceIndex!].method
          for method in service.method {
            XCTAssert(originalMethods.contains(method))
          }
          for messageType in fileDescriptorProto.messageType {
            XCTAssert(self.protos[protoIndex!].messageType.contains(messageType))
          }
        }
        self.protos.removeAll { $0 == fileDescriptorProto }
      }
      XCTAssert(self.protos.isEmpty)
    } catch {
      XCTFail(error.localizedDescription)
    }
  }
}
