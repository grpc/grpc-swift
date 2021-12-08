/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import EchoModel
import GRPC
import XCTest

internal final class EchoMetadataTests: GRPCTestCase {
  private func testServiceDescriptor(_ description: GRPCServiceDescriptor) {
    XCTAssertEqual(description.name, "Echo")
    XCTAssertEqual(description.fullName, "echo.Echo")

    XCTAssertEqual(description.methods.count, 4)

    if let get = description.methods.first(where: { $0.name == "Get" }) {
      self._testGet(get)
    } else {
      XCTFail("No 'Get' method found")
    }

    if let collect = description.methods.first(where: { $0.name == "Collect" }) {
      self._testCollect(collect)
    } else {
      XCTFail("No 'Collect' method found")
    }

    if let expand = description.methods.first(where: { $0.name == "Expand" }) {
      self._testExpand(expand)
    } else {
      XCTFail("No 'Expand' method found")
    }

    if let update = description.methods.first(where: { $0.name == "Update" }) {
      self._testUpdate(update)
    } else {
      XCTFail("No 'Update' method found")
    }
  }

  private func _testGet(_ description: GRPCMethodDescriptor) {
    XCTAssertEqual(description.name, "Get")
    XCTAssertEqual(description.fullName, "echo.Echo/Get")
    XCTAssertEqual(description.path, "/echo.Echo/Get")
    XCTAssertEqual(description.type, .unary)
  }

  private func _testCollect(_ description: GRPCMethodDescriptor) {
    XCTAssertEqual(description.name, "Collect")
    XCTAssertEqual(description.fullName, "echo.Echo/Collect")
    XCTAssertEqual(description.path, "/echo.Echo/Collect")
    XCTAssertEqual(description.type, .clientStreaming)
  }

  private func _testExpand(_ description: GRPCMethodDescriptor) {
    XCTAssertEqual(description.name, "Expand")
    XCTAssertEqual(description.fullName, "echo.Echo/Expand")
    XCTAssertEqual(description.path, "/echo.Echo/Expand")
    XCTAssertEqual(description.type, .serverStreaming)
  }

  private func _testUpdate(_ description: GRPCMethodDescriptor) {
    XCTAssertEqual(description.name, "Update")
    XCTAssertEqual(description.fullName, "echo.Echo/Update")
    XCTAssertEqual(description.path, "/echo.Echo/Update")
    XCTAssertEqual(description.type, .bidirectionalStreaming)
  }

  func testServiceDescriptor() {
    self.testServiceDescriptor(Echo_EchoClientMetadata.serviceDescriptor)
    self.testServiceDescriptor(Echo_EchoServerMetadata.serviceDescriptor)

    #if swift(>=5.5)
    if #available(macOS 12, *) {
      self.testServiceDescriptor(Echo_EchoAsyncClient.serviceDescriptor)
    }
    #endif
  }

  func testGet() {
    self._testGet(Echo_EchoClientMetadata.Methods.get)
    self._testGet(Echo_EchoServerMetadata.Methods.get)
  }

  func testCollect() {
    self._testCollect(Echo_EchoClientMetadata.Methods.collect)
    self._testCollect(Echo_EchoServerMetadata.Methods.collect)
  }

  func testExpand() {
    self._testExpand(Echo_EchoClientMetadata.Methods.expand)
    self._testExpand(Echo_EchoServerMetadata.Methods.expand)
  }

  func testUpdate() {
    self._testUpdate(Echo_EchoClientMetadata.Methods.update)
    self._testUpdate(Echo_EchoServerMetadata.Methods.update)
  }
}
