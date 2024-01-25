/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import EchoModel
import GRPC
import NIOCore
import NIOExtras
import NIOPosix

@main
@available(macOS 10.15, *)
struct PCAP: AsyncParsableCommand {
  @Option(help: "The port to connect to")
  var port = 1234

  func run() async throws {
    // Create an `EventLoopGroup`.
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try! group.syncShutdownGracefully()
    }

    // The filename for the .pcap file to write to.
    let path = "packet-capture-example.pcap"
    let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(
      path: path
    ) { error in
      print("Failed to write with error '\(error)' for path '\(path)'")
    }

    // Ensure that we close the file sink when we're done with it.
    defer {
      try! fileSink.syncClose()
    }

    let channel = try GRPCChannelPool.with(
      target: .host("localhost", port: self.port),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    ) {
      $0.debugChannelInitializer = { channel in
        // Create the PCAP handler and add it to the start of the channel pipeline. If this example
        // used TLS we would likely want to place the handler in a different position in the
        // pipeline so that the captured packets in the trace would not be encrypted.
        let writePCAPHandler = NIOWritePCAPHandler(mode: .client, fileSink: fileSink.write(buffer:))
        return channel.eventLoop.makeCompletedFuture(
          Result {
            try channel.pipeline.syncOperations.addHandler(writePCAPHandler, position: .first)
          }
        )
      }
    }

    // Create a client.
    let echo = Echo_EchoAsyncClient(channel: channel)

    let messages = ["foo", "bar", "baz", "thud", "grunt", "gorp"].map { text in
      Echo_EchoRequest.with { $0.text = text }
    }

    do {
      for try await response in echo.update(messages) {
        print("Received response '\(response.text)'")
      }
      print("RPC completed successfully")
    } catch {
      print("RPC failed with error '\(error)'")
    }

    print("Try opening '\(path)' in Wireshark or with 'tcpdump -r \(path)'")

    try await echo.channel.close().get()
  }
}
