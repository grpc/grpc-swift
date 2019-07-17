/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import XCTest

class GRPCStatusMessageMarshallerTests: GRPCTestCase {
  func testASCIIMarshallingAndUnmarshalling() {
    XCTAssertEqual(GRPCStatusMessageMarshaller.marshall("Hello, World!"), "Hello, World!")
    XCTAssertEqual(GRPCStatusMessageMarshaller.unmarshall("Hello, World!"), "Hello, World!")
  }

  func testPercentMarshallingAndUnmarshalling() {
    XCTAssertEqual(GRPCStatusMessageMarshaller.marshall("%"), "%25")
    XCTAssertEqual(GRPCStatusMessageMarshaller.unmarshall("%25"), "%")

    XCTAssertEqual(GRPCStatusMessageMarshaller.marshall("25%"), "25%25")
    XCTAssertEqual(GRPCStatusMessageMarshaller.unmarshall("25%25"), "25%")
  }

  func testUnicodeMarshalling() {
    XCTAssertEqual(GRPCStatusMessageMarshaller.marshall("🚀"), "%F0%9F%9A%80")
    XCTAssertEqual(GRPCStatusMessageMarshaller.unmarshall("%F0%9F%9A%80"), "🚀")

    let message = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"
    let marshalled = "%09%0Atest with whitespace%0D%0Aand Unicode BMP %E2%98%BA and non-BMP %F0%9F%98%88%09%0A"
    XCTAssertEqual(GRPCStatusMessageMarshaller.marshall(message), marshalled)
    XCTAssertEqual(GRPCStatusMessageMarshaller.unmarshall(marshalled), message)
  }
}
