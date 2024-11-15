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

import Testing

@testable import GRPCCore

@Suite("ServerInterceptorPipelineOperation")
struct ServerInterceptorPipelineOperationTests {
  @Suite("Applies to")
  struct AppliesToTests {
    @Test
    func all() async throws {
      let operation = ServerInterceptorPipelineOperation.apply(
        .requestCounter(.init()),
        to: .all
      )

      #expect(operation.applies(to: MethodDescriptor(service: "foo", method: "bar")))
      #expect(operation.applies(to: MethodDescriptor(service: "foo", method: "baz")))
      #expect(operation.applies(to: MethodDescriptor(service: "bar", method: "foo")))
      #expect(operation.applies(to: MethodDescriptor(service: "bar", method: "baz")))
    }

    @Test
    func serviceSpecific() async throws {
      let operation = ServerInterceptorPipelineOperation.apply(
        .requestCounter(.init()),
        to: .services(Set([ServiceDescriptor(package: "pkg", service: "foo")]))
      )

      #expect(operation.applies(to: MethodDescriptor(service: "pkg.foo", method: "bar")))
      #expect(operation.applies(to: MethodDescriptor(service: "pkg.foo", method: "baz")))

      #expect(!operation.applies(to: MethodDescriptor(service: "pkg.bar", method: "foo")))
      #expect(!operation.applies(to: MethodDescriptor(service: "pkg.bar", method: "baz")))
    }

    @Test
    func methodSpecific() async throws {
      let operation = ServerInterceptorPipelineOperation.apply(
        .requestCounter(.init()),
        to: .methods(Set([MethodDescriptor(service: "bar", method: "foo")]))
      )

      #expect(operation.applies(to: MethodDescriptor(service: "bar", method: "foo")))
      
      #expect(!operation.applies(to: MethodDescriptor(service: "foo", method: "bar")))
      #expect(!operation.applies(to: MethodDescriptor(service: "foo", method: "baz")))
      #expect(!operation.applies(to: MethodDescriptor(service: "bar", method: "baz")))
    }
  }
}
