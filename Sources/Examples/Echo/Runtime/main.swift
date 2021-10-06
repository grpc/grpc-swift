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
import ArgumentParser
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCSampleData
import Logging
import NIO
import NIOSSL

// MARK: - Argument parsing

enum RPC: String, ExpressibleByArgument {
  case get
  case collect
  case expand
  case update
}

struct Echo: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "An example to run and call a simple gRPC service for echoing messages.",
    subcommands: [Server.self, Client.self]
  )

  struct Server: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Start a gRPC server providing the Echo service."
    )

    @Option(help: "The port to listen on for new connections")
    var port = 1234

    @Flag(help: "Whether TLS should be used or not")
    var tls = false

    func run() throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }
      do {
        try startEchoServer(group: group, port: self.port, useTLS: self.tls)
      } catch {
        print("Error running server: \(error)")
      }
    }
  }

  struct Client: ParsableCommand {
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

    func run() throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }

      let client = try makeClient(
        group: group,
        port: self.port,
        useTLS: self.tls,
        useInterceptor: self.intercept
      )
      defer {
        try! client.channel.close().wait()
      }

      for _ in 0 ..< self.iterations {
        callRPC(self.rpc, using: client, message: self.message)
      }
    }
  }
}

// MARK: - Server / Client

func startEchoServer(group: EventLoopGroup, port: Int, useTLS: Bool) throws {
  let builder: Server.Builder

  if useTLS {
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
  } else {
    print("starting insecure server")
    builder = Server.insecure(group: group)
  }

  let server = try builder.withServiceProviders([EchoProvider()])
    .bind(host: "localhost", port: port)
    .wait()

  print("started server: \(server.channel.localAddress!)")

  // This blocks to keep the main thread from finishing while the server runs,
  // but the server never exits. Kill the process to stop it.
  try server.onClose.wait()
}

func makeClient(
  group: EventLoopGroup,
  port: Int,
  useTLS: Bool,
  useInterceptor: Bool
) throws -> Echo_EchoClient {
  let security: GRPCChannelPool.Configuration.TransportSecurity

  if useTLS {
    // We're using some self-signed certs here: check they aren't expired.
    let caCert = SampleCertificate.ca
    let clientCert = SampleCertificate.client
    precondition(
      !caCert.isExpired && !clientCert.isExpired,
      "SSL certificates are expired. Please submit an issue at https://github.com/grpc/grpc-swift."
    )

    let tlsConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(clientCert.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([caCert.certificate])
    )

    security = .tls(tlsConfiguration)
  } else {
    security = .plaintext
  }

  let channel = try GRPCChannelPool.with(
    target: .host("localhost", port: port),
    transportSecurity: security,
    eventLoopGroup: group
  )

  return Echo_EchoClient(
    channel: channel,
    interceptors: useInterceptor ? ExampleClientInterceptorFactory() : nil
  )
}

func callRPC(_ rpc: RPC, using client: Echo_EchoClient, message: String) {
  do {
    switch rpc {
    case .get:
      try echoGet(client: client, message: message)
    case .collect:
      try echoCollect(client: client, message: message)
    case .expand:
      try echoExpand(client: client, message: message)
    case .update:
      try echoUpdate(client: client, message: message)
    }
  } catch {
    print("\(rpc) RPC failed: \(error)")
  }
}

func echoGet(client: Echo_EchoClient, message: String) throws {
  // Get is a unary call.
  let get = client.get(.with { $0.text = message })

  // Register a callback for the response:
  get.response.whenComplete { result in
    switch result {
    case let .success(response):
      print("get receieved: \(response.text)")
    case let .failure(error):
      print("get failed with error: \(error)")
    }
  }

  // wait() for the call to terminate
  let status = try get.status.wait()
  print("get completed with status: \(status.code)")
}

func echoCollect(client: Echo_EchoClient, message: String) throws {
  // Collect is a client streaming call
  let collect = client.collect()

  // Split the messages and map them into requests
  let messages = message.components(separatedBy: " ").map { part in
    Echo_EchoRequest.with { $0.text = part }
  }

  // Stream the to the service (this can also be done on individual requests using `sendMessage`).
  collect.sendMessages(messages, promise: nil)
  // Close the request stream.
  collect.sendEnd(promise: nil)

  // Register a callback for the response:
  collect.response.whenComplete { result in
    switch result {
    case let .success(response):
      print("collect receieved: \(response.text)")
    case let .failure(error):
      print("collect failed with error: \(error)")
    }
  }

  // wait() for the call to terminate
  let status = try collect.status.wait()
  print("collect completed with status: \(status.code)")
}

func echoExpand(client: Echo_EchoClient, message: String) throws {
  // Expand is a server streaming call; provide a response handler.
  let expand = client.expand(.with { $0.text = message }) { response in
    print("expand received: \(response.text)")
  }

  // wait() for the call to terminate
  let status = try expand.status.wait()
  print("expand completed with status: \(status.code)")
}

func echoUpdate(client: Echo_EchoClient, message: String) throws {
  // Update is a bidirectional streaming call; provide a response handler.
  let update = client.update { response in
    print("update received: \(response.text)")
  }

  // Split the messages and map them into requests
  let messages = message.components(separatedBy: " ").map { part in
    Echo_EchoRequest.with { $0.text = part }
  }

  // Stream the to the service (this can also be done on individual requests using `sendMessage`).
  update.sendMessages(messages, promise: nil)
  // Close the request stream.
  update.sendEnd(promise: nil)

  // wait() for the call to terminate
  let status = try update.status.wait()
  print("update completed with status: \(status.code)")
}

Echo.main()
