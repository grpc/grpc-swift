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

      return NameResolver(results: RPCAsyncSequence(wrapping: stream), updateMode: .pull)
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
}
