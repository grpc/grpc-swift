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
import Testing

@Suite
struct MethodDescriptorTests {
  @Test("Fully qualified name")
  @available(gRPCSwift 2.0, *)
  func testFullyQualifiedName() {
    let descriptor = MethodDescriptor(fullyQualifiedService: "foo.bar", method: "Baz")
    #expect(descriptor.service == ServiceDescriptor(fullyQualifiedService: "foo.bar"))
    #expect(descriptor.method == "Baz")
    #expect(descriptor.fullyQualifiedMethod == "foo.bar/Baz")
  }

  @Test("CustomStringConvertible")
  @available(gRPCSwift 2.0, *)
  func description() {
    let descriptor = MethodDescriptor(
      service: ServiceDescriptor(fullyQualifiedService: "foo.Foo"),
      method: "Bar"
    )

    #expect(String(describing: descriptor) == "foo.Foo/Bar")
  }
}
