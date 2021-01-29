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
import Dispatch
import EchoModel
import GRPC
import Logging
import NIO
import NIOExtras

// Create a logger.
let logger = Logger(label: "gRPC PCAP Demo")

// Closing file sinks is blocking, it therefore can't be done on an EventLoop.
let fileSinkCloseQueue = DispatchQueue(label: "io.grpc")
let fileSinkCloseGroup = DispatchGroup()
defer {
  // Make sure we wait for all file sinks to be closed before we exit.
  fileSinkCloseGroup.wait()
  logger.info("Done!")
}

/// Adds a `NIOWritePCAPHandler` to the given channel.
///
/// A file sink will also be created to write the PCAP to `./channel-{ID}.pcap` where `{ID}` is
/// an identifier created from the given `channel`. The file sink will be closed when the channel
/// closes and will notify the `fileSinkCloseGroup` when it has been closed.
///
/// - Parameter channel: The channel to add the PCAP handler to.
/// - Returns: An `EventLoopFuture` indicating whether the PCAP handler was successfully added.
func addPCAPHandler(toChannel channel: Channel) -> EventLoopFuture<Void> {
  // The debug initializer can be called multiple times. We'll use the object ID of the channel
  // to disambiguate between the files.
  let channelID = ObjectIdentifier(channel)
  let path = "./channel-\(channelID).pcap"

  logger.info("Creating fileSink for path '\(path)'")

  do {
    // Create a file sink.
    let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink
      .fileSinkWritingToFile(path: path) { error in
        logger.error("💥 Failed to write with error '\(error)' for path '\(path)'")
      }

    logger.info("✅ Successfully created fileSink for path '\(path)'")

    // We need to close the file sink when we're done. It can't be closed from the event loop so
    // we'll use a dispatch queue instead.
    fileSinkCloseGroup.enter()
    channel.closeFuture.whenComplete { _ in
      fileSinkCloseQueue.async {
        do {
          try fileSink.syncClose()
        } catch {
          logger.error("💥 Failed to close fileSink with error '\(error)' for path '\(path)'")
        }
      }
      fileSinkCloseGroup.leave()
    }

    // Add the handler to the pipeline.
    let handler = NIOWritePCAPHandler(mode: .client, fileSink: fileSink.write(buffer:))
    // We're not using TLS in this example so ".first" is the right place.
    return channel.pipeline.addHandler(handler, position: .first)
  } catch {
    logger.error("💥 Failed to create fileSink with error '\(error)' for path '\(path)'")
    return channel.eventLoop.makeFailedFuture(error)
  }
}

struct PCAP: ParsableCommand {
  @Option(help: "The port to connect to")
  var port = 1234

  func run() throws {
    // Create an `EventLoopGroup`.
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try! group.syncShutdownGracefully()
    }

    // Create a channel.
    let channel = ClientConnection.insecure(group: group)
      // Set the debug initializer: it will add a handler to each created channel to write a PCAP when
      // the channel is closed.
      .withDebugChannelInitializer(addPCAPHandler(toChannel:))
      // We're connecting to our own server here; we'll disable connection re-establishment.
      .withConnectionReestablishment(enabled: false)
      // Connect!
      .connect(host: "localhost", port: self.port)

    // Create a client.
    let echo = Echo_EchoClient(channel: channel)

    // Start an RPC.
    let update = echo.update { response in
      logger.info("Received response '\(response.text)'")
    }

    // Send some requests.
    for text in ["foo", "bar", "baz", "thud", "grunt", "gorp"] {
      update.sendMessage(.with { $0.text = text }).whenSuccess {
        logger.info("Sent request '\(text)'")
      }
    }

    // Close the request stream.
    update.sendEnd(promise: nil)

    // Once the RPC finishes close the connection.
    let closed = update.status.flatMap { status -> EventLoopFuture<Void> in
      if status.isOk {
        logger.info("✅ RPC completed successfully")
      } else {
        logger.error("💥 RPC failed with status '\(status)'")
      }
      logger.info("Closing channel")
      return channel.close()
    }

    // Wait for the channel to be closed.
    try closed.wait()
  }
}

PCAP.main()
