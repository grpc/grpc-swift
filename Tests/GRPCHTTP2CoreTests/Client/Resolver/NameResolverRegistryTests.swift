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

import AsyncDNSResolver
import GRPCCore
import XCTest

@testable import GRPCHTTP2Core

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
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.DNS.self))
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.IPv4.self))
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.IPv6.self))
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.UnixDomainSocket.self))
    XCTAssert(resolvers.containsFactory(ofType: NameResolvers.VirtualSocket.self))
    XCTAssertEqual(resolvers.count, 5)
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
      XCTAssertNil(result.serviceConfig)
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
      XCTAssertNil(result.serviceConfig)
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
      XCTAssertNil(result.serviceConfig)
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
      XCTAssertNil(result.serviceConfig)
    }
  }

  func testUDSResolver() async throws {
    let factory = NameResolvers.UnixDomainSocket()
    let resolver = factory.resolver(for: .unixDomainSocket(path: "/foo"))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The UDS resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.unixDomainSocket(path: "/foo")])])
      XCTAssertNil(result.serviceConfig)
    }
  }

  func testVSOCKResolver() async throws {
    let factory = NameResolvers.VirtualSocket()
    let resolver = factory.resolver(for: .vsock(contextID: .any, port: .any))

    XCTAssertEqual(resolver.updateMode, .pull)

    // The VSOCK resolver always returns the same values.
    var iterator = resolver.names.makeAsyncIterator()
    for _ in 0 ..< 1000 {
      let result = try await XCTUnwrapAsync { try await iterator.next() }
      XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.vsock(contextID: .any, port: .any)])])
      XCTAssertNil(result.serviceConfig)
    }
  }

  func testDNSResolverWithoutServiceConfig() async throws {
    let dns = StaticDNSResolver(
      aRecords: [
        "example.com": [ARecord(address: IPAddress.IPv4(address: "31.41.59.26"), ttl: nil)]
      ]
    )

    let factory = NameResolvers.DNS(
      resolver: AsyncDNSResolver(dns),
      fetchServiceConfiguration: false
    )

    let resolver = factory.resolver(for: .dns(host: "example.com", port: 42))
    XCTAssertEqual(resolver.updateMode, .pull)
    var iterator = resolver.names.makeAsyncIterator()
    let result = try await XCTUnwrapAsync { try await iterator.next() }

    XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.ipv4(host: "31.41.59.26", port: 42)])])
    XCTAssertNil(result.serviceConfiguration)
  }

  func testDNSResolverWithSingleServiceConfigChoice() async throws {
    let txt = """
      grpc_config=[
        {
          "serviceConfig": {}
        }
      ]
      """

    try await self.testDNSResolverWithServiceConfig(txtRecords: [txt]) {
      XCTAssertEqual($0, .success(ServiceConfiguration()))
    }
  }

  func testDNSResolverWithMultipleServiceConfigs() async throws {
    // The first valid choice is picked, i.e. empty.
    let txt = """
      grpc_config=[
        {
          "serviceConfig": {}
        },
        {
          "serviceConfig": {
            "retryThrottling": {
              "maxTokens": 10,
              "tokenRatio": 0.1
            }
          }
        }
      ]
      """

    try await self.testDNSResolverWithServiceConfig(txtRecords: [txt]) {
      XCTAssertEqual($0, .success(ServiceConfiguration()))
    }
  }

  func testDNSResolverWithMultipleServiceConfigsAcrossRecords() async throws {
    // The first valid choice is picked, i.e. empty.
    let records: [String] = [
      """
      grpc_config=[
        {
          "serviceConfig": {}
        }
      ]
      """,
      """
      grpc_config=[
        {
          "serviceConfig": {
            "retryThrottling": {
              "maxTokens": 10,
              "tokenRatio": 0.1
            }
          }
        }
      ]
      """,
    ]

    try await self.testDNSResolverWithServiceConfig(txtRecords: records) {
      XCTAssertEqual($0, .success(ServiceConfiguration()))
    }
  }

  func testDNSResolverWithMultipleServiceConfigChoices() async throws {
    // If multiple service config choices are present then only the first which meets all picking
    // criteria is used.
    //
    // The criteria includes:
    // - the language of the client (e.g. must be "swift")
    // - a percentage
    // - the hostname of the client
    //
    // All criteria must match for a config to be selected. If any property is missing then that
    // property is considered to be matched.
    //
    // This test generates all valid and invalid combinations and checks that only a valid
    // combination is picked.
    enum Choice: CaseIterable, Hashable {
      case accept
      case reject
      case missing
    }

    var accepted = [(language: Choice, percentage: Choice, hostname: Choice)]()
    var rejected = [(language: Choice, percentage: Choice, hostname: Choice)]()

    for language in Choice.allCases {
      for percentage in Choice.allCases {
        for hostname in Choice.allCases {
          if language == .reject || percentage == .reject || hostname == .reject {
            rejected.append((language, percentage, hostname))
          } else {
            accepted.append((language, percentage, hostname))
          }
        }
      }
    }

    let hostname = System.hostname()
    let wrongHostname = hostname + ".not"

    func makeServiceConfigChoice(
      language languageChoice: Choice,
      percentage percentageChoice: Choice,
      hostname hostnameChoice: Choice,
      serviceConfig: ServiceConfiguration = ServiceConfiguration()
    ) -> ServiceConfigChoice {
      let language: [String]
      switch languageChoice {
      case .accept:
        language = ["some-other-lang", "swift", "not-swift"]
      case .reject:
        language = ["not-swift"]
      case .missing:
        language = []
      }

      let percentage: Int?
      switch percentageChoice {
      case .accept:
        percentage = 100
      case .reject:
        percentage = 0
      case .missing:
        percentage = nil
      }

      let hostnames: [String]
      switch hostnameChoice {
      case .accept:
        hostnames = [wrongHostname, hostname]
      case .reject:
        hostnames = [wrongHostname]
      case .missing:
        hostnames = []
      }

      return ServiceConfigChoice(
        language: language,
        percentage: percentage,
        hostname: hostnames,
        configuration: serviceConfig
      )
    }

    // Generate all invalid choices with an empty service config.
    let rejectedChoices = rejected.map {
      makeServiceConfigChoice(
        language: $0.language,
        percentage: $0.percentage,
        hostname: $0.hostname
      )
    }

    // Generate all valid choices with a non-empty service config.
    let json = JSONEncoder()

    // Create a non-empty service config for the acceptable config.
    let policy = try ServiceConfiguration.RetryThrottlingPolicy(maxTokens: 10, tokenRatio: 0.1)
    let serviceConfig = ServiceConfiguration(retryThrottlingPolicy: policy)

    for choice in accepted {
      let acceptableChoice = makeServiceConfigChoice(
        language: choice.language,
        percentage: choice.percentage,
        hostname: choice.percentage,
        serviceConfig: serviceConfig
      )

      // Include all rejected choices followed by one acceptable choice.
      let choices = rejectedChoices + [acceptableChoice]
      let encoded = try json.encode(choices)
      let jsonString = String(decoding: encoded, as: UTF8.self)
      let txtRecord = "grpc_config=\(jsonString)"

      try await self.testDNSResolverWithServiceConfig(txtRecords: [txtRecord]) { serviceConfig in
        let expected = ServiceConfiguration(
          retryThrottlingPolicy: try ServiceConfiguration.RetryThrottlingPolicy(
            maxTokens: 10,
            tokenRatio: 0.1
          )
        )
        XCTAssertEqual(serviceConfig, .success(expected))
      }
    }
  }

  func testDNSResolverIgnoresIrrelevantTxtRecords() async throws {
    let txtRecords: [String] = [
      "unrelated-to-grpc-config",
      #"grpc_config=[{"serviceConfig":{}}]"#,
      "also-unrelated-to-grpc-config",
    ]

    try await self.testDNSResolverWithServiceConfig(txtRecords: txtRecords) {
      XCTAssertEqual($0, .success(ServiceConfiguration()))
    }
  }

  func testDNSResolverGetsIPv4AndIPv6Endpoints() async throws {
    let dns = StaticDNSResolver(
      aRecords: [
        "example.com": [
          ARecord(address: IPAddress.IPv4(address: "1.2.3.4"), ttl: nil),
          ARecord(address: IPAddress.IPv4(address: "1.2.3.5"), ttl: nil),
          ARecord(address: IPAddress.IPv4(address: "1.2.3.6"), ttl: nil),
        ]
      ],
      aaaaRecords: [
        "example.com": [
          AAAARecord(address: IPAddress.IPv6(address: "::1"), ttl: nil),
          AAAARecord(address: IPAddress.IPv6(address: "::2"), ttl: nil),
          AAAARecord(address: IPAddress.IPv6(address: "::3"), ttl: nil),
        ]
      ]
    )

    let factory = NameResolvers.DNS(
      resolver: AsyncDNSResolver(dns),
      fetchServiceConfiguration: false
    )

    let resolver = factory.resolver(for: .dns(host: "example.com", port: 42))
    XCTAssertEqual(resolver.updateMode, .pull)
    var iterator = resolver.names.makeAsyncIterator()
    let result = try await XCTUnwrapAsync { try await iterator.next() }

    XCTAssertNil(result.serviceConfiguration)
    XCTAssertEqual(result.endpoints.count, 6)

    let expectedEndpoints: [Endpoint] = [
      Endpoint(addresses: [.ipv4(host: "1.2.3.4", port: 42)]),
      Endpoint(addresses: [.ipv4(host: "1.2.3.5", port: 42)]),
      Endpoint(addresses: [.ipv4(host: "1.2.3.6", port: 42)]),
      Endpoint(addresses: [.ipv6(host: "::1", port: 42)]),
      Endpoint(addresses: [.ipv6(host: "::2", port: 42)]),
      Endpoint(addresses: [.ipv6(host: "::3", port: 42)]),
    ]

    XCTAssertEqual(Set(result.endpoints), Set(expectedEndpoints))
  }

  func testDNSResolverGetsEndpointsIfConfigParsingFails() async throws {
    let txtRecords: [String] = ["grpc_config=invalid"]
    try await self.testDNSResolverWithServiceConfig(txtRecords: txtRecords) { result in
      switch result {
      case .success, nil:
        XCTFail("Expected failure")
      case .failure(let error):
        XCTAssertEqual(error.code, .internalError)
      }
    }
  }

  private func testDNSResolverWithServiceConfig(
    txtRecords: [String],
    validate: (Result<ServiceConfiguration, RPCError>?) throws -> Void = { _ in }
  ) async throws {
    let dns = StaticDNSResolver(
      aRecords: [
        "example.com": [ARecord(address: IPAddress.IPv4(address: "1.2.3.4"), ttl: nil)]
      ],
      txtRecords: [
        "_grpc_config.example.com": txtRecords.map { TXTRecord(txt: $0) }
      ]
    )

    let factory = NameResolvers.DNS(
      resolver: AsyncDNSResolver(dns),
      fetchServiceConfiguration: true
    )

    let resolver = factory.resolver(for: .dns(host: "example.com", port: 42))
    XCTAssertEqual(resolver.updateMode, .pull)
    var iterator = resolver.names.makeAsyncIterator()
    let result = try await XCTUnwrapAsync { try await iterator.next() }

    XCTAssertEqual(result.endpoints, [Endpoint(addresses: [.ipv4(host: "1.2.3.4", port: 42)])])
    try validate(result.serviceConfiguration)
  }
}

private struct StaticDNSResolver: DNSResolver {
  var aRecords: [String: [ARecord]]
  var aaaaRecords: [String: [AAAARecord]]
  var txtRecords: [String: [TXTRecord]]

  init(
    aRecords: [String: [ARecord]] = [:],
    aaaaRecords: [String: [AAAARecord]] = [:],
    txtRecords: [String: [TXTRecord]] = [:]
  ) {
    self.aRecords = aRecords
    self.aaaaRecords = aaaaRecords
    self.txtRecords = txtRecords
  }

  func queryA(name: String) async throws -> [ARecord] {
    return self.aRecords[name] ?? []
  }

  func queryAAAA(name: String) async throws -> [AAAARecord] {
    return self.aaaaRecords[name] ?? []
  }

  func queryTXT(name: String) async throws -> [TXTRecord] {
    return self.txtRecords[name] ?? []
  }

  func queryNS(name: String) async throws -> NSRecord {
    return NSRecord(nameservers: [])
  }

  func queryCNAME(name: String) async throws -> String? {
    return nil
  }

  func querySOA(name: String) async throws -> SOARecord? {
    return nil
  }

  func queryPTR(name: String) async throws -> PTRRecord {
    return PTRRecord(names: [])
  }

  func queryMX(name: String) async throws -> [MXRecord] {
    return []
  }

  func querySRV(name: String) async throws -> [SRVRecord] {
    return []
  }
}
