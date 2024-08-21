/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import ArgumentParser
import EchoImplementation
import EchoModel
import GRPC
import GRPCSampleData
import NIOCore
import NIOPosix

#if canImport(NIOSSL)
import NIOSSL
#endif

// MARK: - Argument parsing

enum RPC: String, ExpressibleByArgument {
  case get
  case collect
  case expand
  case update
}

@main
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Echo: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "An example to run and call a simple gRPC service for echoing messages.",
    subcommands: [Server.self, Client.self]
  )

  struct Server: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Start a gRPC server providing the Echo service."
    )

    @Option(help: "The port to listen on for new connections")
    var port = 1234

    @Flag(help: "Whether TLS should be used or not")
    var tls = false

    func run() async throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }
      do {
        try await startEchoServer(group: group, port: self.port, useTLS: self.tls)
      } catch {
        print("Error running server: \(error)")
      }
    }
  }

  struct Client: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Calls an RPC on the Echo server."
    )

    @Option(help: "The port to connect to")
    var port = 1234

    @Flag(help: "Whether TLS should be used or not")
    var tls = false

    @Flag(help: "Whether interceptors should be used, see 'docs/interceptors-tutorial.md'.")
    var intercept = false

    @Option(help: "RPC to call ('get', 'collect', 'expand', 'update').")
    var rpc: RPC = .get

    @Option(help: "How many RPCs to do.")
    var iterations: Int = 1

    @Argument(help: "Message to echo")
    var message: String

    func run() async throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }

      let client = makeClient(
        group: group,
        port: self.port,
        useTLS: self.tls,
        useInterceptor: self.intercept
      )
      defer {
        try! client.channel.close().wait()
      }

      for _ in 0 ..< self.iterations {
        await callRPC(self.rpc, using: client, message: self.message)
      }
    }
  }
}

// MARK: - Server

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func startEchoServer(group: EventLoopGroup, port: Int, useTLS: Bool) async throws {
  let builder: Server.Builder

  if useTLS {
    #if canImport(NIOSSL)
    // We're using some self-signed certs here: check they aren't expired.
    let caCert = SampleCertificate.ca
    let serverCert = SampleCertificate.server
    precondition(
      !caCert.isExpired && !serverCert.isExpired,
      "SSL certificates are expired. Please submit an issue at https://github.com/grpc/grpc-swift."
    )

    builder = Server.usingTLSBackedByNIOSSL(
      on: group,
      certificateChain: [serverCert.certificate],
      privateKey: SamplePrivateKey.server
    )
    .withTLS(trustRoots: .certificates([caCert.certificate]))
    print("starting secure server")
    #else
    fatalError("'useTLS: true' passed to \(#function) but NIOSSL is not available")
    #endif  // canImport(NIOSSL)
  } else {
    print("starting insecure server")
    builder = Server.insecure(group: group)
  }

  let server = try await builder.withServiceProviders([EchoAsyncProvider()])
    .bind(host: "localhost", port: port)
    .get()

  print("started server: \(server.channel.localAddress!)")

  // This blocks to keep the main thread from finishing while the server runs,
  // but the server never exits. Kill the process to stop it.
  try await server.onClose.get()
}

// MARK: - Client

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func makeClient(
  group: EventLoopGroup,
  port: Int,
  useTLS: Bool,
  useInterceptor: Bool
) -> Echo_EchoAsyncClient {
  let builder: ClientConnection.Builder

  if useTLS {
    #if canImport(NIOSSL)
    // We're using some self-signed certs here: check they aren't expired.
    let caCert = SampleCertificate.ca
    let clientCert = SampleCertificate.client
    precondition(
      !caCert.isExpired && !clientCert.isExpired,
      "SSL certificates are expired. Please submit an issue at https://github.com/grpc/grpc-swift."
    )

    builder = ClientConnection.usingTLSBackedByNIOSSL(on: group)
      .withTLS(certificateChain: [clientCert.certificate])
      .withTLS(privateKey: SamplePrivateKey.client)
      .withTLS(trustRoots: .certificates([caCert.certificate]))
    #else
    fatalError("'useTLS: true' passed to \(#function) but NIOSSL is not available")
    #endif  // canImport(NIOSSL)
  } else {
    builder = ClientConnection.insecure(group: group)
  }

  // Start the connection and create the client:
  let connection = builder.connect(host: "localhost", port: port)

  return Echo_EchoAsyncClient(
    channel: connection,
    interceptors: useInterceptor ? ExampleClientInterceptorFactory() : nil
  )
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func callRPC(_ rpc: RPC, using client: Echo_EchoAsyncClient, message: String) async {
  do {
    switch rpc {
    case .get:
      try await echoGet(client: client, message: message)
    case .collect:
      try await echoCollect(client: client, message: message)
    case .expand:
      try await echoExpand(client: client, message: message)
    case .update:
      try await echoUpdate(client: client, message: message)
    }
  } catch {
    print("\(rpc) RPC failed: \(error)")
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func echoGet(client: Echo_EchoAsyncClient, message: String) async throws {
  let response = try await client.get(.with { $0.text = message })
  print("get received: \(response.text)")
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func echoCollect(client: Echo_EchoAsyncClient, message: String) async throws {
  let messages = message.components(separatedBy: " ").map { part in
    Echo_EchoRequest.with { $0.text = part }
  }
  let response = try await client.collect(messages)
  print("collect received: \(response.text)")
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func echoExpand(client: Echo_EchoAsyncClient, message: String) async throws {
  for try await response in client.expand((.with { $0.text = message })) {
    print("expand received: \(response.text)")
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func echoUpdate(client: Echo_EchoAsyncClient, message: String) async throws {
  let requests = message.components(separatedBy: " ").map { word in
    Echo_EchoRequest.with { $0.text = word }
  }
  for try await response in client.update(requests) {
    print("update received: \(response.text)")
  }
}
