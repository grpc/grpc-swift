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

import GRPCCore
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class RPCRouterTests: XCTestCase {
  func testEmptyRouter() async throws {
    var router = RPCRouter()
    XCTAssertEqual(router.count, 0)
    XCTAssertEqual(router.methods, [])
    XCTAssertFalse(router.hasHandler(forMethod: MethodDescriptor(service: "foo", method: "bar")))
    XCTAssertFalse(router.removeHandler(forMethod: MethodDescriptor(service: "foo", method: "bar")))
  }

  func testRegisterMethod() async throws {
    var router = RPCRouter()
    let method = MethodDescriptor(service: "foo", method: "bar")
    router.registerHandler(
      forMethod: method,
      deserializer: IdentityDeserializer(),
      serializer: IdentitySerializer()
    ) { _ in
      throw RPCError(code: .failedPrecondition, message: "Shouldn't be called")
    }

    XCTAssertEqual(router.count, 1)
    XCTAssertEqual(router.methods, [method])
    XCTAssertTrue(router.hasHandler(forMethod: method))
  }

  func testRemoveMethod() async throws {
    var router = RPCRouter()
    let method = MethodDescriptor(service: "foo", method: "bar")
    router.registerHandler(
      forMethod: method,
      deserializer: IdentityDeserializer(),
      serializer: IdentitySerializer()
    ) { _ in
      throw RPCError(code: .failedPrecondition, message: "Shouldn't be called")
    }

    XCTAssertTrue(router.removeHandler(forMethod: method))
    XCTAssertFalse(router.hasHandler(forMethod: method))
    XCTAssertEqual(router.count, 0)
    XCTAssertEqual(router.methods, [])
  }
}
