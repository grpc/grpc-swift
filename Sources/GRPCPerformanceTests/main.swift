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
import NIO
import NIOSSL
import EchoImplementation
import EchoModel
import Logging

struct ConnectionFactory {
  var configuration: ClientConnection.Configuration

  func makeConnection() -> ClientConnection {
    return ClientConnection(configuration: self.configuration)
  }

  func makeEchoClient() -> Echo_EchoServiceClient {
    return Echo_EchoServiceClient(connection: self.makeConnection())
  }
}

protocol Benchmark: class {
  func setUp() throws
  func tearDown() throws
  func run() throws
}

/// Tests unary throughput by sending requests on a single connection.
///
/// Requests are sent in batches of (up-to) 100 requests. This is due to
/// https://github.com/apple/swift-nio-http2/issues/87#issuecomment-483542401.
class UnaryThroughput: Benchmark {
  let factory: ConnectionFactory
  let requests: Int
  let requestLength: Int
  var client: Echo_EchoServiceClient!
  var request: String!

  init(factory: ConnectionFactory, requests: Int, requestLength: Int) {
    self.factory = factory
    self.requests = requests
    self.requestLength = requestLength
  }

  func setUp() throws {
    self.client = self.factory.makeEchoClient()
    self.request = String(repeating: "0", count: self.requestLength)
  }

  func run() throws {
    let batchSize = 100

    for lowerBound in stride(from: 0, to: self.requests, by: batchSize) {
      let upperBound = min(lowerBound + batchSize, self.requests)

      let requests = (lowerBound..<upperBound).map { _ in
        client.get(Echo_EchoRequest.with { $0.text = self.request }).response
      }

      try EventLoopFuture.andAllSucceed(requests, on: self.client.connection.eventLoop).wait()
    }
  }

  func tearDown() throws {
    try self.client.connection.close().wait()
  }
}

/// Tests bidirectional throughput by sending requests over a single stream.
///
/// Requests are sent in batches of (up-to) 100 requests. This is due to
/// https://github.com/apple/swift-nio-http2/issues/87#issuecomment-483542401.
class BidirectionalThroughput: UnaryThroughput {
  override func run() throws {
    let update = self.client.update { _ in }

    for _ in 0..<self.requests {
      update.sendMessage(Echo_EchoRequest.with { $0.text = self.request }, promise: nil)
    }
    update.sendEnd(promise: nil)

    _ = try update.status.wait()
  }
}

/// Tests the number of connections that can be created.
final class ConnectionCreationThroughput: Benchmark {
  let factory: ConnectionFactory
  let connections: Int
  var createdConnections: [ClientConnection] = []

  class ConnectionReadinessDelegate: ConnectivityStateDelegate {
    let promise: EventLoopPromise<Void>

    var ready: EventLoopFuture<Void> {
      return promise.futureResult
    }

    init(promise: EventLoopPromise<Void>) {
      self.promise = promise
    }

    func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
      switch newState {
      case .ready:
        promise.succeed(())

      case .shutdown:
        promise.fail(GRPCStatus(code: .unavailable, message: nil))

      default:
        break
      }
    }
  }

  init(factory: ConnectionFactory, connections: Int) {
    self.factory = factory
    self.connections = connections
  }

  func setUp() throws { }

  func run() throws {
    let connectionsAndDelegates: [(ClientConnection, ConnectionReadinessDelegate)] = (0..<connections).map { _ in
      let promise = self.factory.configuration.eventLoopGroup.next().makePromise(of: Void.self)
      var configuration = self.factory.configuration
      let delegate = ConnectionReadinessDelegate(promise: promise)
      configuration.connectivityStateDelegate = delegate
      return (ClientConnection(configuration: configuration), delegate)
    }

    self.createdConnections = connectionsAndDelegates.map { connection, _ in connection }
    let futures = connectionsAndDelegates.map { _, delegate in delegate.ready }
    try EventLoopFuture.andAllSucceed(
      futures,
      on: self.factory.configuration.eventLoopGroup.next()
    ).wait()
  }

  func tearDown() throws {
    let connectionClosures = self.createdConnections.map {
      $0.close()
    }

    try EventLoopFuture.andAllSucceed(
      connectionClosures,
      on: self.factory.configuration.eventLoopGroup.next()).wait()
  }
}

/// The results of a benchmark.
struct BenchmarkResults {
  let benchmarkDescription: String
  let durations: [TimeInterval]

  /// Returns the results as a comma separated string.
  ///
  /// The format of the string is as such:
  /// <name>, <number of results> [, <duration>]
  var asCSV: String {
    let items = [self.benchmarkDescription, String(self.durations.count)] + self.durations.map { String($0) }
    return items.joined(separator: ", ")
  }
}

/// Runs the given benchmark multiple times, recording the wall time for each iteration.
///
/// - Parameter description: A description of the benchmark.
/// - Parameter benchmark: The benchmark to run.
/// - Parameter repeats: The number of times to run the benchmark.
func measure(description: String, benchmark: Benchmark, repeats: Int) -> BenchmarkResults {
  var durations: [TimeInterval] = []
  for _ in 0..<repeats {
    do {
      try benchmark.setUp()

      let start = Date()
      try benchmark.run()
      let end = Date()

      durations.append(end.timeIntervalSince(start))
    } catch {
      // If tearDown fails now then there's not a lot we can do!
      try? benchmark.tearDown()
      return BenchmarkResults(benchmarkDescription: description, durations: [])
    }

    do {
      try benchmark.tearDown()
    } catch {
      return BenchmarkResults(benchmarkDescription: description, durations: [])
    }
  }

  return BenchmarkResults(benchmarkDescription: description, durations: durations)
}

/// Makes an SSL context if one is required. Note that the CLI tool doesn't support optional values,
/// so we use empty strings for the paths if we don't require SSL.
///
/// This function will terminate the program if it is not possible to create an SSL context.
///
/// - Parameter caCertificatePath: The path to the CA certificate PEM file.
/// - Parameter certificatePath: The path to the certificate.
/// - Parameter privateKeyPath: The path to the private key.
/// - Parameter server: Whether this is for the server or not.
private func makeServerTLSConfiguration(caCertificatePath: String, certificatePath: String, privateKeyPath: String) throws -> Server.Configuration.TLS? {
  // Commander doesn't have Optional options; we use empty strings to indicate no value.
  guard certificatePath.isEmpty == privateKeyPath.isEmpty &&
    privateKeyPath.isEmpty == caCertificatePath.isEmpty else {
      print("Paths for CA certificate, certificate and private key must be provided")
      exit(1)
  }

  // No need to check them all because of the guard statement above.
  if caCertificatePath.isEmpty {
    return nil
  }

  return .init(
    certificateChain: try NIOSSLCertificate.fromPEMFile(certificatePath).map { .certificate($0) },
    privateKey: .file(privateKeyPath),
    trustRoots: .file(caCertificatePath)
  )
}

private func makeClientTLSConfiguration(
  caCertificatePath: String,
  certificatePath: String,
  privateKeyPath: String
) throws -> ClientConnection.Configuration.TLS? {
  // Commander doesn't have Optional options; we use empty strings to indicate no value.
  guard certificatePath.isEmpty == privateKeyPath.isEmpty &&
    privateKeyPath.isEmpty == caCertificatePath.isEmpty else {
      print("Paths for CA certificate, certificate and private key must be provided")
      exit(1)
  }

  // No need to check them all because of the guard statement above.
  if caCertificatePath.isEmpty {
    return nil
  }

  return .init(
    certificateChain: try NIOSSLCertificate.fromPEMFile(certificatePath).map { .certificate($0) },
    privateKey: .file(privateKeyPath),
    trustRoots: .file(caCertificatePath)
  )
}

enum Benchmarks: String, CaseIterable {
  case unaryThroughputSmallRequests = "unary_throughput_small"
  case unaryThroughputLargeRequests = "unary_throughput_large"
  case bidirectionalThroughputSmallRequests = "bidi_throughput_small"
  case bidirectionalThroughputLargeRequests = "bidi_throughput_large"
  case connectionThroughput = "connection_throughput"

  static let smallRequest = 8
  static let largeRequest = 1 << 16

  var description: String {
    switch self {
    case .unaryThroughputSmallRequests:
      return "10k unary requests of size \(Benchmarks.smallRequest)"

    case .unaryThroughputLargeRequests:
      return "10k unary requests of size \(Benchmarks.largeRequest)"

    case .bidirectionalThroughputSmallRequests:
      return "20k bidirectional messages of size \(Benchmarks.smallRequest)"

    case .bidirectionalThroughputLargeRequests:
      return "10k bidirectional messages of size \(Benchmarks.largeRequest)"

    case .connectionThroughput:
      return "100 connections created"
    }
  }

  func makeBenchmark(factory: ConnectionFactory) -> Benchmark {
    switch self {
    case .unaryThroughputSmallRequests:
      return UnaryThroughput(factory: factory, requests: 10_000, requestLength: Benchmarks.smallRequest)

    case .unaryThroughputLargeRequests:
      return UnaryThroughput(factory: factory, requests: 10_000, requestLength: Benchmarks.largeRequest)

    case .bidirectionalThroughputSmallRequests:
      return BidirectionalThroughput(factory: factory, requests: 20_000, requestLength: Benchmarks.smallRequest)

    case .bidirectionalThroughputLargeRequests:
      return BidirectionalThroughput(factory: factory, requests: 10_000, requestLength: Benchmarks.largeRequest)

    case .connectionThroughput:
      return ConnectionCreationThroughput(factory: factory, connections: 100)
    }
  }

  func run(using factory: ConnectionFactory, repeats: Int = 10) -> BenchmarkResults {
    let benchmark = self.makeBenchmark(factory: factory)
    return measure(description: self.description, benchmark: benchmark, repeats: repeats)
  }
}

enum Command {
  case listBenchmarks
  case benchmark(name: String, host: String, port: Int, tls: (ca: String, cert: String)?)
  case server(port: Int, tls: (ca: String, cert: String, key: String)?)

  init?(from args: [String]) {
    guard !args.isEmpty else {
      return nil
    }

    var args = args
    let command = args.removeFirst()
    switch command {
    case "server":
      guard let port = args.popLast().flatMap(Int.init) else {
        return nil
      }

      let caPath = args.suffixOfFirst(prefixedWith: "--caPath=")
      let certPath = args.suffixOfFirst(prefixedWith: "--certPath=")
      let keyPath = args.suffixOfFirst(prefixedWith: "--keyPath=")

      // We need all or nothing here:
      switch (caPath, certPath, keyPath) {
      case let (.some(ca), .some(cert), .some(key)):
        self = .server(port: port, tls: (ca: ca, cert: cert, key: key))
      case (.none, .none, .none):
        self = .server(port: port, tls: nil)
      default:
        return nil
      }

    case "benchmark":
      guard let name = args.popLast(),
        let port = args.popLast().flatMap(Int.init),
        let host = args.popLast()
        else {
          return nil
      }

      let caPath = args.suffixOfFirst(prefixedWith: "--caPath=")
      let certPath = args.suffixOfFirst(prefixedWith: "--certPath=")
      // We need all or nothing here:
      switch (caPath, certPath) {
      case let (.some(ca), .some(cert)):
        self = .benchmark(name: name, host: host, port: port, tls: (ca: ca, cert: cert))
      case (.none, .none):
        self = .benchmark(name: name, host: host, port: port, tls: nil)
      default:
        return nil
      }

    case "list_benchmarks":
      self = .listBenchmarks

    default:
      return nil
    }
  }
}

func printUsageAndExit(program: String) -> Never {
  print("""
  Usage: \(program) COMMAND [OPTIONS...]

  benchmark:
    Run the given benchmark (see 'list_benchmarks' for possible options) against a server on the
    specified host and port. TLS may be used by spefifying the path to the PEM formatted
    certificate and CA certificate.

      benchmark [--ca=CA --cert=CERT] HOST PORT BENCHMARK_NAME

    Note: eiether all or none of CA and CERT must be provided.

  list_benchmarks:
    List the available benchmarks to run.

  server:
    Start the server on the given PORT. TLS may be used by specifying the paths to the PEM formatted
    certificate, private key and CA certificate.

      server [--ca=CA --cert=CERT --key=KEY] PORT

    Note: eiether all or none of CA, CERT and KEY must be provided.
  """)
  exit(1)
}

fileprivate extension Array where Element == String {
  func suffixOfFirst(prefixedWith prefix: String) -> String? {
    return self.first {
      $0.hasPrefix(prefix)
    }.map {
      String($0.dropFirst(prefix.count))
    }
  }
}

func main(args: [String]) {
  var args = args
  let program = args.removeFirst()
  guard let command = Command(from: args) else {
    printUsageAndExit(program: program)
  }

  switch command {
  case let .server(port: port, tls: tls):
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer {
      try! group.syncShutdownGracefully()
    }

    // Quieten the logs.
    LoggingSystem.bootstrap {
      var handler = StreamLogHandler.standardOutput(label: $0)
      handler.logLevel = .warning
      return handler
    }

    do {
      let configuration = try Server.Configuration(
        target: .hostAndPort("localhost", port),
        eventLoopGroup: group,
        serviceProviders: [EchoProvider()],
        tls: tls.map { tlsArgs in
          return .init(
            certificateChain: try NIOSSLCertificate.fromPEMFile(tlsArgs.cert).map { .certificate($0) },
            privateKey: .file(tlsArgs.key),
            trustRoots: .file(tlsArgs.ca)
          )
        }
      )

      let server = try Server.start(configuration: configuration).wait()
      print("server started on port: \(server.channel.localAddress?.port ?? port)")

      // Stop the program from exiting.
      try? server.onClose.wait()
    } catch {
      print("unable to start server: \(error)")
      exit(1)
    }

  case let .benchmark(name: name, host: host, port: port, tls: tls):
    guard let benchmark = Benchmarks(rawValue: name) else {
      printUsageAndExit(program: program)
    }

    // Quieten the logs.
    LoggingSystem.bootstrap {
      var handler = StreamLogHandler.standardOutput(label: $0)
      handler.logLevel = .critical
      return handler
    }

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try! group.syncShutdownGracefully()
    }

    do {
      let configuration = try ClientConnection.Configuration(
        target: .hostAndPort(host, port),
        eventLoopGroup: group,
        tls: tls.map { tlsArgs in
          return .init(
            certificateChain: try NIOSSLCertificate.fromPEMFile(tlsArgs.cert).map { .certificate($0) },
            trustRoots: .file(tlsArgs.ca)
          )
        }
      )

      let factory = ConnectionFactory(configuration: configuration)
      let results = benchmark.run(using: factory)
      print(results.asCSV)
    } catch {
      print("unable to run benchmark: \(error)")
      exit(1)
    }

  case .listBenchmarks:
    Benchmarks.allCases.forEach {
      print($0.rawValue)
    }
  }
}

main(args: CommandLine.arguments)
