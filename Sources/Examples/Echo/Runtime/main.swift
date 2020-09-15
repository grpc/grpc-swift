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
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCSampleData
import Logging
import NIO
import NIOSSL

// MARK: - Argument parsing

enum RPC: String {
  case get
  case collect
  case expand
  case update
}

enum Command {
  case server(port: Int, useTLS: Bool)
  case client(host: String, port: Int, useTLS: Bool, rpc: RPC, message: String)

  init?(from args: [String]) {
    guard !args.isEmpty else {
      return nil
    }

    var args = args
    switch args.removeFirst() {
    case "server":
      guard args.count == 1 || args.count == 2,
        let port = args.popLast().flatMap(Int.init),
        let useTLS = Command.parseTLSArg(args.popLast())
      else {
        return nil
      }
      self = .server(port: port, useTLS: useTLS)

    case "client":
      guard args.count == 4 || args.count == 5,
        let message = args.popLast(),
        let rpc = args.popLast().flatMap(RPC.init),
        let port = args.popLast().flatMap(Int.init),
        let host = args.popLast(),
        let useTLS = Command.parseTLSArg(args.popLast())
      else {
        return nil
      }
      self = .client(host: host, port: port, useTLS: useTLS, rpc: rpc, message: message)

    default:
      return nil
    }
  }

  private static func parseTLSArg(_ arg: String?) -> Bool? {
    switch arg {
    case .some("--tls"):
      return true
    case .none, .some("--notls"):
      return false
    default:
      return nil
    }
  }
}

func printUsageAndExit(program: String) -> Never {
  print("""
  Usage: \(program) COMMAND [OPTIONS...]

  Commands:
    server [--tls|--notls] PORT                     Starts the echo server on the given port.

    client [--tls|--notls] HOST PORT RPC MESSAGE    Connects to the echo server on the given host
                                                    host and port and calls the RPC with the
                                                    provided message. See below for a list of
                                                    possible RPCs.

  RPCs:
    * get      (unary)
    * collect  (client streaming)
    * expand   (server streaming)
    * update   (bidirectional streaming)
  """)
  exit(1)
}

func main(args: [String]) {
  var args = args
  let program = args.removeFirst()
  guard let command = Command(from: args) else {
    printUsageAndExit(program: program)
  }

  // Okay, we're nearly ready to start, create an `EventLoopGroup` most suitable for our platform.
  let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
  defer {
    try! group.syncShutdownGracefully()
  }

  // Now run the server/client.
  switch command {
  case let .server(port: port, useTLS: useTLS):
    do {
      try startEchoServer(group: group, port: port, useTLS: useTLS)
    } catch {
      print("Error running server: \(error)")
    }

  case let .client(host: host, port: port, useTLS: useTLS, rpc: rpc, message: message):
    let client = makeClient(group: group, host: host, port: port, useTLS: useTLS)
    defer {
      try! client.channel.close().wait()
    }
    callRPC(rpc, using: client, message: message)
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

    builder = Server.secure(
      group: group,
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

func makeClient(group: EventLoopGroup, host: String, port: Int, useTLS: Bool) -> Echo_EchoClient {
  let builder: ClientConnection.Builder

  if useTLS {
    // We're using some self-signed certs here: check they aren't expired.
    let caCert = SampleCertificate.ca
    let clientCert = SampleCertificate.client
    precondition(
      !caCert.isExpired && !clientCert.isExpired,
      "SSL certificates are expired. Please submit an issue at https://github.com/grpc/grpc-swift."
    )

    builder = ClientConnection.secure(group: group)
      .withTLS(certificateChain: [clientCert.certificate])
      .withTLS(privateKey: SamplePrivateKey.client)
      .withTLS(trustRoots: .certificates([caCert.certificate]))
  } else {
    builder = ClientConnection.insecure(group: group)
  }

  // Start the connection and create the client:
  let connection = builder.connect(host: host, port: port)
  return Echo_EchoClient(channel: connection)
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

main(args: CommandLine.arguments)
