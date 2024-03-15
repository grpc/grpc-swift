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

import struct Foundation.Data
import class Foundation.JSONDecoder

extension ResolvableTargets {
  /// A resolvable target for IPv4 addresses.
  ///
  /// IPv4 addresses can be resolved by the ``NameResolvers/DNS``.
  public struct DNS: ResolvableTarget {
    /// The host to resolve via DNS.
    public var host: String

    /// The port to use with resolved addresses.
    public var port: Int

    /// Create a new DNS target.
    /// - Parameters:
    ///   - host: The host to resolve via DNS.
    ///   - port: The port to use with resolved addresses.
    public init(host: String, port: Int) {
      self.host = host
      self.port = port
    }
  }
}

extension ResolvableTarget where Self == ResolvableTargets.DNS {
  /// Creates a new resolvable DNS target.
  /// - Parameters:
  ///   - host: The host address to resolve.
  ///   - port: The port to use for each resolved address.
  /// - Returns: A ``ResolvableTarget``.
  public static func dns(host: String, port: Int = 443) -> Self {
    return Self(host: host, port: port)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension NameResolvers {
  /// A ``NameResolverFactory`` for ``ResolvableTargets/IPv4`` targets.
  ///
  /// The name resolver for a given target always produces the same values, with one endpoint per
  /// address in the target. The service configuration can be specified when creating the resolver
  /// factory and defaults to `ServiceConfiguration.default`.
  public struct DNS: NameResolverFactory {
    public typealias Target = ResolvableTargets.DNS

    private let dnsResolver: AsyncDNSResolver
    private let fetchServiceConfiguration: Bool

    /// Create a new DNS name resolver factory.
    ///
    /// - Parameters:
    ///   - resolver: The DNS resolver to use.
    ///   - fetchServiceConfiguration: Whether service config should be fetched from DNS TXT
    ///       records.
    public init(resolver: AsyncDNSResolver, fetchServiceConfiguration: Bool) {
      self.dnsResolver = resolver
      self.fetchServiceConfiguration = fetchServiceConfiguration
    }

    /// Creates a new DNS resolver factory.
    ///
    /// - Parameters:
    ///   - fetchServiceConfiguration: Whether service config should be fetched from DNS TXT
    ///       records.
    public init(fetchServiceConfiguration: Bool) throws {
      self.dnsResolver = try AsyncDNSResolver()
      self.fetchServiceConfiguration = fetchServiceConfiguration
    }

    public func resolver(for target: Target) -> NameResolver {
      let resolver = Self.Resolver(
        dns: self.dnsResolver,
        fetchServiceConfiguration: self.fetchServiceConfiguration,
        target: target
      )

      return NameResolver(names: RPCAsyncSequence(wrapping: resolver), updateMode: .pull)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension NameResolvers.DNS {
  struct Resolver {
    /// The underlying raw DNS resolver.
    let dns: AsyncDNSResolver
    /// The target to resolve.
    let target: ResolvableTargets.DNS
    /// Whether service configuration should be fetched from DNS TXT records.
    let fetchServiceConfiguration: Bool
    /// JSON decoder used for decoding service configuration.
    let decoder: JSONDecoder
    /// The hostname of the system the resolver is running on. May be used when a service config
    /// is picked from a list of config choices.
    let hostname: String

    /// Prefix for DNS TXT records containing gRPC config.
    private static let txtRecordPrefix = "grpc_config="
    /// Name prefix for DNS TXT records containing gRPC config. E.g. if the name to resolve is
    /// `grpc.io` then the name of the TXT records to resolve is `_grpc_config.grpc.io`.
    private static let txtRecordNamePrefix = "_grpc_config."

    init(
      dns: AsyncDNSResolver,
      fetchServiceConfiguration: Bool,
      target: ResolvableTargets.DNS
    ) {
      self.dns = dns
      self.target = target
      self.fetchServiceConfiguration = fetchServiceConfiguration
      self.decoder = JSONDecoder()
      self.hostname = System.hostname()
    }

    func resolve() async throws -> NameResolutionResult {
      // Kick off address resolution
      async let _endpoints = self.resolveEndpoints()

      // Fetch the service configuration and pick an appropriate choice.
      let serviceConfig: Result<ServiceConfiguration, RPCError>?
      if self.fetchServiceConfiguration {
        switch await self.resolveServiceConfigChoices() {
        case .success(let choices):
          serviceConfig = self.selectServiceConfig(choices: choices).map { .success($0) }
        case .failure(let error):
          serviceConfig = .failure(error)
        }
      } else {
        serviceConfig = nil
      }

      let endpoints = try await _endpoints.get()
      return NameResolutionResult(endpoints: endpoints, serviceConfiguration: serviceConfig)
    }

    private func resolveEndpoints() async -> Result<[Endpoint], RPCError> {
      return await withTaskGroup(of: Result<[Endpoint], RPCError>.self) { group in
        group.addTask {
          do {
            let records = try await self.dns.queryA(name: self.target.host)
            let endpoints = records.map { record in
              let address = SocketAddress.ipv4(host: record.address.address, port: self.target.port)
              return Endpoint(addresses: [address])
            }
            return .success(endpoints)
          } catch {
            let error = RPCError(
              code: .internalError,
              message: "DNS lookup for A records associated with '\(self.target.host)' failed",
              cause: error
            )
            return .failure(error)
          }
        }

        group.addTask {
          do {
            let records = try await self.dns.queryAAAA(name: self.target.host)
            let endpoints = records.map { record in
              let address = SocketAddress.ipv6(host: record.address.address, port: self.target.port)
              return Endpoint(addresses: [address])
            }
            return .success(endpoints)
          } catch {
            let error = RPCError(
              code: .internalError,
              message: "DNS lookup for AAAA records associated with '\(self.target.host)' failed",
              cause: error
            )
            return .failure(error)
          }
        }

        var all = [Endpoint]()
        for await result in group {
          switch result {
          case .success(let endpoints):
            all.append(contentsOf: endpoints)
          case .failure(let error):
            return .failure(error)
          }
        }

        return .success(all)
      }
    }

    private func resolveServiceConfigChoices() async -> Result<[ServiceConfigChoice], RPCError> {
      let name = Self.txtRecordNamePrefix + self.target.host

      do {
        let records = try await self.dns.queryTXT(name: name)
        return self.parseTXTRecords(records)
      } catch {
        let error = RPCError(
          code: .internalError,
          message: "DNS lookup for TXT records associated with '\(name)' failed",
          cause: error
        )
        return .failure(error)
      }
    }

    private func parseTXTRecords(
      _ records: [TXTRecord]
    ) -> Result<[ServiceConfigChoice], RPCError> {
      var allChoices = [ServiceConfigChoice]()

      for record in records {
        // The records are prefixed with "grpc_config=". The suffix is an array of service config
        // choice objects encoded as a JSON array.
        guard record.txt.hasPrefix(Self.txtRecordPrefix) else { continue }

        // Drop the prefix, the rest of the content should be a JSON array.
        let json = Data(record.txt.utf8.dropFirst(Self.txtRecordPrefix.utf8.count))

        do {
          let choices = try self.decoder.decode([ServiceConfigChoice].self, from: json)
          allChoices.append(contentsOf: choices)
        } catch {
          let error = RPCError(
            code: .internalError,
            message: "Can't decode service_config choice.",
            cause: error
          )
          return .failure(error)
        }
      }

      return .success(allChoices)
    }

    private func selectServiceConfig(choices: [ServiceConfigChoice]) -> ServiceConfiguration? {
      let choice = choices.first { $0.select(hostname: self.hostname) }
      return choice?.configuration
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension NameResolvers.DNS.Resolver: AsyncSequence {
  typealias Element = NameResolutionResult

  func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(resolver: self)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    typealias Element = NameResolutionResult

    private let resolver: NameResolvers.DNS.Resolver
    private var finished = false

    init(resolver: NameResolvers.DNS.Resolver) {
      self.resolver = resolver
    }

    mutating func next() async throws -> NameResolutionResult? {
      if self.finished {
        return nil
      } else if Task.isCancelled {
        self.finished = true
        throw CancellationError()
      }

      do {
        return try await self.resolver.resolve()
      } catch {
        self.finished = true
        throw error
      }
    }
  }
}

// Service configuration provided by DNS is contained in a JSON object with this shape.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ServiceConfigChoice: Codable {
  var language: [String]
  var percentage: Int?
  var hostname: [String]
  var configuration: ServiceConfiguration

  enum CodingKeys: CodingKey {
    case clientLanguage
    case percentage
    case clientHostname
    case serviceConfig
  }

  init(
    language: [String] = [],
    percentage: Int? = nil,
    hostname: [String] = [],
    configuration: ServiceConfiguration
  ) {
    self.language = language
    self.percentage = percentage
    self.hostname = hostname
    self.configuration = configuration
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.language = try container.decodeIfPresent([String].self, forKey: .clientLanguage) ?? []
    self.percentage = try container.decodeIfPresent(Int.self, forKey: .percentage)
    self.hostname = try container.decodeIfPresent([String].self, forKey: .clientHostname) ?? []
    self.configuration = try container.decode(ServiceConfiguration.self, forKey: .serviceConfig)

    if let percentage = self.percentage, percentage < 0 || percentage > 100 {
      throw RPCError(
        code: .internalError,
        message: "Invalid service config choice percentage '\(percentage)' (must be 0...100)"
      )
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if !self.language.isEmpty {
      try container.encode(self.language, forKey: .clientLanguage)
    }
    if !self.hostname.isEmpty {
      try container.encode(self.hostname, forKey: .clientHostname)
    }
    try container.encodeIfPresent(self.percentage, forKey: .percentage)
    try container.encode(self.configuration, forKey: .serviceConfig)
  }

  func select(hostname: String) -> Bool {
    // All three conditions must pass. Empty arrays count as matching all values.
    let containsSwift = self.language.contains { $0.lowercased() == "swift" }
    guard containsSwift || self.language.isEmpty else { return false }

    let canarySelected = Int.random(in: 1 ... 100) <= (self.percentage ?? 100)
    guard canarySelected else { return false }

    let containsHostname = self.hostname.contains(hostname)
    return containsHostname || self.hostname.isEmpty
  }
}
