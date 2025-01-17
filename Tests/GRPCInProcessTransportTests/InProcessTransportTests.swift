/*
 * Copyright 2024-2025, gRPC Authors All rights reserved.
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

import GRPCCore
import GRPCInProcessTransport
import Testing

@Suite("InProcess transport")
struct InProcessTransportTests {
  private static let cancellationModes = ["await-cancelled", "with-cancellation-handler"]

  private func withTestServerAndClient(
    execute: (
      GRPCServer<InProcessTransport.Server>,
      GRPCClient<InProcessTransport.Client>
    ) async throws -> Void
  ) async throws {
    try await withThrowingDiscardingTaskGroup { group in
      let inProcess = InProcessTransport()

      let server = GRPCServer(transport: inProcess.server, services: [TestService()])
      group.addTask {
        try await server.serve()
      }

      let client = GRPCClient(transport: inProcess.client)
      group.addTask {
        try await client.runConnections()
      }

      try await execute(server, client)
    }
  }

  @Test("RPC cancelled by graceful shutdown", arguments: Self.cancellationModes)
  func cancelledByGracefulShutdown(mode: String) async throws {
    try await self.withTestServerAndClient { server, client in
      try await client.serverStreaming(
        request: ClientRequest(message: mode),
        descriptor: .testCancellation,
        serializer: UTF8Serializer(),
        deserializer: UTF8Deserializer(),
        options: .defaults
      ) { response in
        // Got initial metadata, begin shutdown to cancel the RPC.
        server.beginGracefulShutdown()

        // Now wait for the response.
        let messages = try await response.messages.reduce(into: []) { $0.append($1) }
        #expect(messages == ["isCancelled=true"])
      }

      // Finally, shutdown the client so its runConnections() method returns.
      client.beginGracefulShutdown()
    }
  }

  @Test("Peer info")
  func peerInfo() async throws {
    try await self.withTestServerAndClient { server, client in
      defer {
        client.beginGracefulShutdown()
        server.beginGracefulShutdown()
      }

      let peerInfo = try await client.unary(
        request: ClientRequest(message: ()),
        descriptor: .peerInfo,
        serializer: VoidSerializer(),
        deserializer: PeerInfoDeserializer(),
        options: .defaults
      ) {
        try $0.message
      }

      #expect(peerInfo.local == peerInfo.remote)
    }
  }
}

private struct TestService: RegistrableRPCService {
  func cancellation(
    request: ServerRequest<String>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<String> {
    switch request.message {
    case "await-cancelled":
      return StreamingServerResponse { body in
        try await context.cancellation.cancelled
        try await body.write("isCancelled=\(context.cancellation.isCancelled)")
        return [:]
      }

    case "with-cancellation-handler":
      let signal = AsyncStream.makeStream(of: Void.self)
      return StreamingServerResponse { body in
        try await withRPCCancellationHandler {
          for await _ in signal.stream {}
          try await body.write("isCancelled=\(context.cancellation.isCancelled)")
          return [:]
        } onCancelRPC: {
          signal.continuation.finish()
        }
      }

    default:
      throw RPCError(code: .invalidArgument, message: "Invalid argument '\(request.message)'")
    }
  }

  func peerInfo(
    request: ServerRequest<Void>,
    context: ServerContext
  ) async throws -> ServerResponse<PeerInfo> {
    let peerInfo = PeerInfo(local: context.localPeer, remote: context.remotePeer)
    return ServerResponse(message: peerInfo)
  }

  func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
    router.registerHandler(
      forMethod: .testCancellation,
      deserializer: UTF8Deserializer(),
      serializer: UTF8Serializer(),
      handler: {
        try await self.cancellation(request: ServerRequest(stream: $0), context: $1)
      }
    )

    router.registerHandler(
      forMethod: .peerInfo,
      deserializer: VoidDeserializer(),
      serializer: PeerInfoSerializer(),
      handler: {
        let response = try await self.peerInfo(
          request: ServerRequest<Void>(stream: $0),
          context: $1
        )
        return StreamingServerResponse(single: response)
      }
    )
  }
}

extension MethodDescriptor {
  fileprivate static let testCancellation = Self(
    fullyQualifiedService: "test",
    method: "cancellation"
  )

  fileprivate static let peerInfo = Self(
    fullyQualifiedService: "test",
    method: "peerInfo"
  )
}

private struct PeerInfo: Codable {
  var local: String
  var remote: String
}

private struct PeerInfoSerializer: MessageSerializer {
  func serialize<Bytes: GRPCContiguousBytes>(_ message: PeerInfo) throws -> Bytes {
    Bytes("\(message.local) \(message.remote)".utf8)
  }
}

private struct PeerInfoDeserializer: MessageDeserializer {
  func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> PeerInfo {
    let stringPeerInfo = serializedMessageBytes.withUnsafeBytes {
      String(decoding: $0, as: UTF8.self)
    }
    let peerInfoComponents = stringPeerInfo.split(separator: " ")
    return PeerInfo(local: String(peerInfoComponents[0]), remote: String(peerInfoComponents[1]))
  }
}

private struct UTF8Serializer: MessageSerializer {
  func serialize<Bytes: GRPCContiguousBytes>(_ message: String) throws -> Bytes {
    Bytes(message.utf8)
  }
}

private struct UTF8Deserializer: MessageDeserializer {
  func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> String {
    serializedMessageBytes.withUnsafeBytes {
      String(decoding: $0, as: UTF8.self)
    }
  }
}

private struct VoidSerializer: MessageSerializer {
  func serialize<Bytes: GRPCContiguousBytes>(_ message: Void) throws -> Bytes {
    Bytes(repeating: 0, count: 0)
  }
}

private struct VoidDeserializer: MessageDeserializer {
  func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws {
  }
}
