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
import GRPCHTTP2Core
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class NameResolverRegistryTests: XCTestCase {
  struct FailingResolver: NameResolverFactory {
    typealias Target = StringTarget

    private let code: RPCError.Code

    init(code: RPCError.Code = .unavailable) {
      self.code = code
    }

    func resolver(for target: NameResolverRegistryTests.StringTarget) -> NameResolver {
      let stream = AsyncThrowingStream(NameResolutionResult.self) {
        $0.yield(with: .failure(RPCError(code: self.code, message: target.value)))
      }

      return NameResolver(names: RPCAsyncSequence(wrapping: stream), updateMode: .pull)
    }
  }

  struct StringTarget: ResolvableTarget {
    var value: String

    init(value: String) {
      self.value = value
    }
  }

  func testEmptyNameResolvers() {
    let resolvers = NameResolverRegistry()
    XCTAssert(resolvers.isEmpty)
    XCTAssertEqual(resolvers.count, 0)
  }

  func testRegisterFactory() async throws {
    var resolvers = NameResolverRegistry()
    resolvers.registerFactory(FailingResolver(code: .unknown))
    XCTAssertEqual(resolvers.count, 1)

    do {
      let resolver = resolvers.makeResolver(for: StringTarget(value: "foo"))
      await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
        var iterator = resolver?.names.makeAsyncIterator()
        _ = try await iterator?.next()
      } errorHandler: { error in
        XCTAssertEqual(error.code, .unknown)
      }
    }

    // Adding a resolver of the same type replaces it. Use the code of the thrown error to
    // distinguish between the instances.
    resolvers.registerFactory(FailingResolver(code: .cancelled))
    XCTAssertEqual(resolvers.count, 1)

    do {
      let resolver = resolvers.makeResolver(for: StringTarget(value: "foo"))
      await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
        var iterator = resolver?.names.makeAsyncIterator()
        _ = try await iterator?.next()
      } errorHandler: { error in
        XCTAssertEqual(error.code, .cancelled)
      }
    }
  }

  func testRemoveFactory() {
    var resolvers = NameResolverRegistry()
    resolvers.registerFactory(FailingResolver())
    XCTAssertEqual(resolvers.count, 1)

    resolvers.removeFactory(ofType: FailingResolver.self)
    XCTAssertEqual(resolvers.count, 0)

    // Removing an unknown factory is a no-op.
    resolvers.removeFactory(ofType: FailingResolver.self)
    XCTAssertEqual(resolvers.count, 0)
  }

  func testContainsFactoryOfType() {
    var resolvers = NameResolverRegistry()
    XCTAssertFalse(resolvers.containsFactory(ofType: FailingResolver.self))

    resolvers.registerFactory(FailingResolver())
    XCTAssertTrue(resolvers.containsFactory(ofType: FailingResolver.self))
  }

  func testContainsFactoryCapableOfResolving() {
    var resolvers = NameResolverRegistry()
    XCTAssertFalse(resolvers.containsFactory(capableOfResolving: StringTarget(value: "")))

    resolvers.registerFactory(FailingResolver())
    XCTAssertTrue(resolvers.containsFactory(capableOfResolving: StringTarget(value: "")))
  }

  func testMakeFailingResolver() async throws {
    var resolvers = NameResolverRegistry()
    XCTAssertNil(resolvers.makeResolver(for: StringTarget(value: "")))

    resolvers.registerFactory(FailingResolver())

    let resolver = try XCTUnwrap(resolvers.makeResolver(for: StringTarget(value: "foo")))
    XCTAssertEqual(resolver.updateMode, .pull)

    var iterator = resolver.names.makeAsyncIterator()
    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      try await iterator.next()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .unavailable)
      XCTAssertEqual(error.message, "foo")
    }
  }

  func testDefaultResolvers() {
    let resolvers = NameResolverRegistry.defaults
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.IPv4.self))
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.IPv6.self))
  }

  func testMakeResolver() {
    let resolvers = NameResolverRegistry()
    XCTAssertNil(resolvers.makeResolver(for: .ipv4(host: "foo")))
  }

  func testCustomResolver() async throws {
    struct EmptyTarget: ResolvableTarget {
      static var scheme: String { "empty" }
    }

    struct CustomResolver: NameResolverFactory {
      func resolver(for target: EmptyTarget) -> NameResolver {
        return NameResolver(
          names: RPCAsyncSequence(wrapping: AsyncStream { $0.finish() }),
          updateMode: .push
        )
      }
    }

    var resolvers = NameResolverRegistry.defaults
    resolvers.registerFactory(CustomResolver())
    let resolver = try XCTUnwrap(resolvers.makeResolver(for: EmptyTarget()))
    XCTAssertEqual(resolver.updateMode, .push)
    for try await _ in resolver.names {
      XCTFail("Expected an empty sequence")
    }
  }

  func testIPv4ResolverForSingleHost() async throws {
    let factory = NameResolvers.IPv4()
    let resolver = factory.resolver(for: .ipv4(host: "foo", port: 1234))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The IPv4 resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.ipv4(host: "foo", port: 1234)])])
      XCTAssertNil(result.serviceConfiguration)
    }
  }

  func testIPv4ResolverForMultipleHosts() async throws {
    let factory = NameResolvers.IPv4()
    let resolver = factory.resolver(for: .ipv4(pairs: [("foo", 443), ("bar", 444)]))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The IPv4 resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(
        result.endpoints,
        [
          Endpoint(addresses: [.ipv4(host: "foo", port: 443)]),
          Endpoint(addresses: [.ipv4(host: "bar", port: 444)]),
        ]
      )
      XCTAssertNil(result.serviceConfiguration)
    }
  }

  func testIPv6ResolverForSingleHost() async throws {
    let factory = NameResolvers.IPv6()
    let resolver = factory.resolver(for: .ipv6(host: "foo", port: 1234))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The IPv6 resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.ipv6(host: "foo", port: 1234)])])
      XCTAssertNil(result.serviceConfiguration)
    }
  }

  func testIPv6ResolverForMultipleHosts() async throws {
    let factory = NameResolvers.IPv6()
    let resolver = factory.resolver(for: .ipv6(pairs: [("foo", 443), ("bar", 444)]))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The IPv6 resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(
        result.endpoints,
        [
          Endpoint(addresses: [.ipv6(host: "foo", port: 443)]),
          Endpoint(addresses: [.ipv6(host: "bar", port: 444)]),
        ]
      )
      XCTAssertNil(result.serviceConfiguration)
    }
  }
}
