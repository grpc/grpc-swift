/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
struct ServiceDescriptorTests {
  @Test(
    "Decompose fully qualified service name",
    arguments: [
      ("foo.bar.baz", "foo.bar", "baz"),
      ("foo.bar", "foo", "bar"),
      ("foo", "", "foo"),
      ("..", ".", ""),
      (".", "", ""),
      ("", "", ""),
    ]
  )
  func packageAndService(fullyQualified: String, package: String, service: String) {
    let descriptor = ServiceDescriptor(fullyQualifiedService: fullyQualified)
    #expect(descriptor.fullyQualifiedService == fullyQualified)
    #expect(descriptor.package == package)
    #expect(descriptor.service == service)
  }

  @Test("CustomStringConvertible")
  func description() {
    let descriptor = ServiceDescriptor(fullyQualifiedService: "foo.Foo")
    #expect(String(describing: descriptor) == "foo.Foo")
  }
}
