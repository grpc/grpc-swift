import Foundation
import SwiftGRPCNIO
import NIO
import NIOSSL
import Commander

struct ConnectionFactory {
  var host: String
  var port: Int
  var group: EventLoopGroup
  var context: NIOSSLContext?
  var serverHostOverride: String?

  func makeConnection() throws -> EventLoopFuture<GRPCClientConnection> {
    return try GRPCClientConnection.start(
      host: self.host,
      port: self.port,
      eventLoopGroup: self.group,
      tls: self.context.map { .custom($0) } ?? .none,
      hostOverride: self.serverHostOverride)
  }

  func makeEchoClient() throws -> EventLoopFuture<Echo_EchoService_NIOClient> {
    return try self.makeConnection().map {
      Echo_EchoService_NIOClient(connection: $0)
    }
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
  var client: Echo_EchoService_NIOClient!
  var request: String!

  init(factory: ConnectionFactory, requests: Int, requestLength: Int) {
    self.factory = factory
    self.requests = requests
    self.requestLength = requestLength
  }

  func setUp() throws {
    self.client = try self.factory.makeEchoClient().wait()
    self.request = String(repeating: "0", count: self.requestLength)
  }

  func run() throws {
    let batchSize = 100

    for lowerBound in stride(from: 0, to: self.requests, by: batchSize) {
      let upperBound = min(lowerBound + batchSize, self.requests)

      let requests = (lowerBound..<upperBound).map { _ in
        client.get(Echo_EchoRequest.with { $0.text = self.request }).response
      }

      try EventLoopFuture.andAllSucceed(requests, on: self.client.connection.channel.eventLoop).wait()
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

  var createdConnections: [EventLoopFuture<GRPCClientConnection>] = []

  init(factory: ConnectionFactory, connections: Int) {
    self.factory = factory
    self.connections = connections
  }

  func setUp() throws { }

  func run() throws {
    self.createdConnections = try (0..<connections).map { _ in
      try self.factory.makeConnection()
    }

    try EventLoopFuture.andAllSucceed(self.createdConnections, on: self.factory.group.next()).wait()
  }

  func tearDown() throws {
    let connectionClosures = self.createdConnections.map {
      $0.flatMap {
        $0.close()
      }
    }

    try EventLoopFuture.andAllSucceed(connectionClosures, on: self.factory.group.next()).wait()
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
private func makeSSLContext(caCertificatePath: String, certificatePath: String, privateKeyPath: String, server: Bool) -> NIOSSLContext? {
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

  let configuration: TLSConfiguration
  if server {
    configuration = .forServer(
      certificateChain: [.file(certificatePath)],
      privateKey: .file(privateKeyPath),
      trustRoots: .file(caCertificatePath),
      applicationProtocols: ["h2"]
    )
  } else {
    configuration = .forClient(
      trustRoots: .file(caCertificatePath),
      certificateChain: [.file(certificatePath)],
      privateKey: .file(privateKeyPath),
      applicationProtocols: ["h2"]
    )
  }

  do {
    return try NIOSSLContext(configuration: configuration)
  } catch {
    print("Unable to create SSL context: \(error)")
    exit(1)
  }
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

let hostOption = Option(
  "host",
  // Use IPv4 to avoid the happy eyeballs delay, this is important when we test the
  // connection throughput.
  default: "127.0.0.1",
  description: "The host to connect to.")

let portOption = Option(
  "port",
  default: 8080,
  description: "The port on the host to connect to.")

let benchmarkOption = Option(
  "benchmarks",
  default: Benchmarks.allCases.map { $0.rawValue }.joined(separator: ","),
  description: "A comma separated list of benchmarks to run. Defaults to all benchmarks.")

let caCertificateOption = Option(
  "ca_certificate",
  default: "",
  description: "The path to the CA certificate to use.")

let certificateOption = Option(
  "certificate",
  default: "",
  description: "The path to the certificate to use.")

let privateKeyOption = Option(
  "private_key",
  default: "",
  description: "The path to the private key to use.")

let hostOverrideOption = Option(
  "hostname_override",
  default: "",
  description: "The expected name of the server to use for TLS.")

Group { group in
  group.command(
    "run_benchmarks",
    benchmarkOption,
    hostOption,
    portOption,
    caCertificateOption,
    certificateOption,
    privateKeyOption,
    hostOverrideOption
  ) { benchmarkNames, host, port, caCertificatePath, certificatePath, privateKeyPath, hostOverride in
    let sslContext = makeSSLContext(
      caCertificatePath: caCertificatePath,
      certificatePath: certificatePath,
      privateKeyPath: privateKeyPath,
      server: false)

    let factory = ConnectionFactory(
      host: host,
      port: port,
      group: MultiThreadedEventLoopGroup(numberOfThreads: 1),
      context: sslContext,
      serverHostOverride: hostOverride.isEmpty ? nil : hostOverride)

    let names = benchmarkNames.components(separatedBy: ",")

    // validate the benchmarks exist before running any
    let benchmarks = names.map { name -> Benchmarks in
      guard let benchnark = Benchmarks(rawValue: name) else {
        print("unknown benchmark: \(name)")
        exit(1)
      }
      return benchnark
    }

    benchmarks.forEach { benchmark in
      let results = benchmark.run(using: factory)
      print(results.asCSV)
    }
  }

  group.command(
    "start_server",
    hostOption,
    portOption,
    caCertificateOption,
    certificateOption,
    privateKeyOption
  ) { host, port, caCertificatePath, certificatePath, privateKeyPath in
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let sslContext = makeSSLContext(
      caCertificatePath: caCertificatePath,
      certificatePath: certificatePath,
      privateKeyPath: privateKeyPath,
      server: true)

    let server: GRPCServer

    do {
      server = try GRPCServer.start(
        hostname: host,
        port: port,
        eventLoopGroup: group,
        serviceProviders: [EchoProviderNIO()],
        tls: sslContext.map { .custom($0) } ?? .none).wait()
    } catch {
      print("unable to start server: \(error)")
      exit(1)
    }

    print("server started on port: \(server.channel.localAddress?.port ?? port)")

    // Stop the program from exiting.
    try? server.onClose.wait()
  }
}.run()
