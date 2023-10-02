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

final class SerializationTests: GRPCTestCase {
  var fileDescriptorProto: Google_Protobuf_FileDescriptorProto!

  override func setUp() {
    super.setUp()
    let binaryFileURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().appendingPathComponent("echo.grpc.reflection.txt")
    let base64EncodedData = try! Data(contentsOf: binaryFileURL)
    let binaryData = Data(base64Encoded: base64EncodedData)!
    self
      .fileDescriptorProto =
      try! Google_Protobuf_FileDescriptorProto(serializedData: binaryData)
  }

  func testFileDescriptorMetadata() throws {
    let name = self.fileDescriptorProto.name
    XCTAssertEqual(name, "echo.proto")

    let syntax = self.fileDescriptorProto.syntax
    XCTAssertEqual(syntax, "proto3")

    let package = self.fileDescriptorProto.package
    XCTAssertEqual(package, "echo")
  }

  func testFileDescriptorMessages() {
    let messages = self.fileDescriptorProto.messageType
    XCTAssertEqual(messages.count, 2)
    for message in messages {
      XCTAssert((message.name == "EchoRequest") || (message.name == "EchoResponse"))
      XCTAssertEqual(message.field.count, 1)
      XCTAssertEqual(message.field.first!.name, "text")
      XCTAssert(message.field.first!.hasNumber)
    }
  }

  func testFileDescriptorServices() {
    let services = self.fileDescriptorProto.service
    XCTAssertEqual(services.count, 1)
    XCTAssertEqual(self.fileDescriptorProto.service.first!.method.count, 4)
    for method in self.fileDescriptorProto.service.first!.method {
      switch method.name {
      case "Get":
        XCTAssertEqual(method.inputType, ".echo.EchoRequest")
        XCTAssertEqual(method.outputType, ".echo.EchoResponse")
      case "Expand":
        XCTAssertEqual(method.inputType, ".echo.EchoRequest")
        XCTAssertEqual(method.outputType, ".echo.EchoResponse")
        XCTAssert(method.serverStreaming)
      case "Collect":
        XCTAssertEqual(method.inputType, ".echo.EchoRequest")
        XCTAssertEqual(method.outputType, ".echo.EchoResponse")
        XCTAssert(method.clientStreaming)
      case "Update":
        XCTAssertEqual(method.inputType, ".echo.EchoRequest")
        XCTAssertEqual(method.outputType, ".echo.EchoResponse")
        XCTAssert(method.clientStreaming)
        XCTAssert(method.serverStreaming)
      default:
        XCTFail("The method name is incorrect.")
      }
    }
  }
}
