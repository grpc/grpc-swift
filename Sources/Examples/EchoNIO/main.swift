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
import Commander
import Dispatch
import Foundation
import NIO
import SwiftGRPCNIO

// Common flags and options
func addressOption(_ address: String) -> Option<String> {
  return Option("address", default: address, description: "address of server")
}

let portOption = Option("port", default: 8080)
let messageOption = Option("message",
                           default: "Testing 1 2 3",
                           description: "message to send")

/// Create en `EchoClient` and wait for it to initialize. Returns nil if initialisation fails.
func makeEchoClient(address: String, port: Int) -> Echo_EchoService_NIOClient? {
  let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  do {
    return try GRPCClient.start(host: address, port: port, eventLoopGroup: eventLoopGroup)
      .map { client in Echo_EchoService_NIOClient(client: client) }
      .wait()
  } catch {
    print("Unable to create an EchoClient: \(error)")
    return nil
  }
}

Group {
  $0.command("serve",
             addressOption("localhost"),
             portOption,
             description: "Run an echo server.") { address, port in
    let sem = DispatchSemaphore(value: 0)
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    print("starting insecure server")
    _ = try! GRPCServer.start(hostname: address,
                              port: port,
                              eventLoopGroup: eventLoopGroup,
                              serviceProviders: [EchoProviderNIO()])
      .wait()

    // This blocks to keep the main thread from finishing while the server runs,
    // but the server never exits. Kill the process to stop it.
    _ = sem.wait()
  }

  $0.command(
    "get",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a unary get()."
  ) { address, port, message in
    print("calling get")
    guard let echo = makeEchoClient(address: address, port: port) else { return }

    var requestMessage = Echo_EchoRequest()
    requestMessage.text = message

    print("get sending: \(requestMessage.text)")
    let get = echo.get(requestMessage)
    get.response.whenSuccess { response in
      print("get received: \(response.text)")
    }

    get.response.whenFailure { error in
      print("get response failed with error: \(error)")
    }

    // wait() on the status to stop the program from exiting.
    do {
      let status = try get.status.wait()
      print("get completed with status: \(status)")
    } catch {
      print("get status failed with error: \(error)")
    }
  }

  $0.command(
    "expand",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a server-streaming expand()."
  ) { address, port, message in
    print("calling expand")
    guard let echo = makeEchoClient(address: address, port: port) else { return }

    let requestMessage = Echo_EchoRequest.with { $0.text = message }

    print("expand sending: \(requestMessage.text)")
    let expand = echo.expand(requestMessage) { response in
      print("expand received: \(response.text)")
    }

    // wait() on the status to stop the program from exiting.
    do {
      let status = try expand.status.wait()
      print("expand completed with status: \(status)")
    } catch {
      print("expand status failed with error: \(error)")
    }
  }

  $0.command(
    "collect",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a client-streaming collect()."
  ) { address, port, message in
    print("calling collect")
    guard let echo = makeEchoClient(address: address, port: port) else { return }

    let collect = echo.collect()

    var queue = collect.newMessageQueue()
    for part in message.components(separatedBy: " ") {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("collect sending: \(requestMessage.text)")
      queue = queue.flatMap { collect.sendMessage(requestMessage) }
    }
    queue.whenSuccess { collect.sendEnd(promise: nil) }

    collect.response.whenSuccess { respone in
      print("collect received: \(respone.text)")
    }

    collect.response.whenFailure { error in
      print("collect response failed with error: \(error)")
    }

    // wait() on the status to stop the program from exiting.
    do {
      let status = try collect.status.wait()
      print("collect completed with status: \(status)")
    } catch {
      print("collect status failed with error: \(error)")
    }
  }

  $0.command(
    "update",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a bidirectional-streaming update()."
  ) { address, port, message in
    print("calling update")
    guard let echo = makeEchoClient(address: address, port: port) else { return }

    let update = echo.update { response in
      print("update received: \(response.text)")
    }

    var queue = update.newMessageQueue()
    for part in message.components(separatedBy: " ") {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("update sending: \(requestMessage.text)")
      queue = queue.flatMap { update.sendMessage(requestMessage) }
    }
    queue.whenSuccess { update.sendEnd(promise: nil) }

    // wait() on the status to stop the program from exiting.
    do {
      let status = try update.status.wait()
      print("update completed with status: \(status)")
    } catch {
      print("update status failed with error: \(error)")
    }
  }
}.run()
