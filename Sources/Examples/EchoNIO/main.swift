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

func makeEchoClient(address: String, port: Int) throws -> EchoClient {
  let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  return try GRPCClient.start(host: address, port: port, eventLoopGroup: eventLoopGroup)
    .map { client in EchoClient(client: client) }
    .wait()
}

Group {
  $0.command(
    "serve",
    addressOption("0.0.0.0"),
    portOption,
    description: "Run an echo server."
  ) { address, port in
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
    let echo = try! makeEchoClient(address: address, port: port)

    var requestMessage = Echo_EchoRequest()
    requestMessage.text = message

    print("get sending: \(requestMessage.text)")
    let get = echo.get(request: requestMessage)
    get.response.whenSuccess { response in
      print("get received: \(response.text)")
    }

    _ = try! get.response.wait()
  }

  $0.command(
    "expand",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a server-streaming expand()."
  ) { address, port, message in
    print("calling expand")
    let echo = try! makeEchoClient(address: address, port: port)

    var requestMessage = Echo_EchoRequest()
    requestMessage.text = message

    print("expand sending: \(requestMessage.text)")
    let expand = echo.expand(request: requestMessage) { response in
      print("expand received: \(response.text)")
    }

    _ = try! expand.status.wait()
  }

  $0.command(
    "collect",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a client-streaming collect()."
  ) { address, port, message in
    print("calling collect")
    let echo = try! makeEchoClient(address: address, port: port)

    let collect = echo.collect()

    for part in message.components(separatedBy: " ") {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("collect sending: \(requestMessage.text)")
      collect.send(.message(requestMessage))
    }
    collect.send(.end)

    collect.response.whenSuccess { resposne in
      print("collect received: \(resposne.text)")
    }

    _ = try! collect.status.wait()
  }

  $0.command(
    "update",
    addressOption("localhost"),
    portOption,
    messageOption,
    description: "Perform a bidirectional-streaming update()."
  ) { address, port, message in
    print("calling update")
    let echo = try! makeEchoClient(address: address, port: port)

    let update = echo.update { response in
      print("update received: \(response.text)")
    }

    for part in message.components(separatedBy: " ") {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("update sending: \(requestMessage.text)")
      update.send(.message(requestMessage))
    }
    update.send(.end)

    _ = try! update.status.wait()
  }
}.run()
