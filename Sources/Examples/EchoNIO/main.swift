/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

let portOption = Option("port",
                        default: "8080",
                        description: "port of server")

Group {
  $0.command("serve",
             addressOption("0.0.0.0"),
             portOption,
             description: "Run an echo server.") { address, port in
    let sem = DispatchSemaphore(value: 0)
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    print("starting insecure server")
    _ = try! GRPCServer.start(hostname: address,
                          port: Int(port)!,
                          eventLoopGroup: eventLoopGroup,
                          serviceProviders: [EchoProviderNIO()])
      .wait()

    // This blocks to keep the main thread from finishing while the server runs,
    // but the server never exits. Kill the process to stop it.
    _ = sem.wait()
  }

}.run()
