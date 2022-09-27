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
import EchoImplementation
import GRPC
import NIO

@_cdecl("ServerFuzzer")
public func test(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
  let bytes = UnsafeRawBufferPointer(start: start, count: count)

  let channel = EmbeddedChannel()
  defer {
    _ = try? channel.finish()
  }

  let configuration = Server.Configuration.default(
    target: .unixDomainSocket("/ignored"),
    eventLoopGroup: channel.eventLoop,
    serviceProviders: [EchoProvider()]
  )

  var buffer = channel.allocator.buffer(capacity: count)
  buffer.writeBytes(bytes)

  do {
    try channel._configureForServerFuzzing(configuration: configuration)
    try channel.writeInbound(buffer)
    channel.embeddedEventLoop.run()
  } catch {
    // We're okay with errors.
  }

  return 0
}
