/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

private import Atomics
internal import GRPCCore

import struct Foundation.Data

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct BenchmarkService: Grpc_Testing_BenchmarkService.ServiceProtocol {
  /// Used to check if the server can be streaming responses.
  private let working = ManagedAtomic<Bool>(true)

  /// One request followed by one response.
  /// The server returns a client payload with the size requested by the client.
  func unaryCall(
    request: ServerRequest.Single<Grpc_Testing_SimpleRequest>
  ) async throws -> ServerResponse.Single<Grpc_Testing_SimpleResponse> {
    // Throw an error if the status is not `ok`. Otherwise, an `ok` status is automatically sent
    // if the request is successful.
    if request.message.responseStatus.isInitialized {
      try self.checkOkStatus(request.message.responseStatus)
    }

    return ServerResponse.Single(
      message: .with {
        $0.payload = Grpc_Testing_Payload.with {
          $0.body = Data(count: Int(request.message.responseSize))
        }
      }
    )
  }

  /// Repeated sequence of one request followed by one response.
  /// The server returns a payload with the size requested by the client for each received message.
  func streamingCall(
    request: ServerRequest.Stream<Grpc_Testing_SimpleRequest>
  ) async throws -> ServerResponse.Stream<Grpc_Testing_SimpleResponse> {
    return ServerResponse.Stream { writer in
      for try await message in request.messages {
        if message.responseStatus.isInitialized {
          try self.checkOkStatus(message.responseStatus)
        }

        let responseMessage = Grpc_Testing_SimpleResponse.with {
          $0.payload = Grpc_Testing_Payload.with {
            $0.body = Data(count: Int(message.responseSize))
          }
        }

        try await writer.write(responseMessage)
      }

      return [:]
    }
  }

  /// Single-sided unbounded streaming from client to server.
  /// The server returns a payload with the size requested by the client once the client does WritesDone.
  func streamingFromClient(
    request: ServerRequest.Stream<Grpc_Testing_SimpleRequest>
  ) async throws -> ServerResponse.Single<Grpc_Testing_SimpleResponse> {
    var responseSize = 0
    for try await message in request.messages {
      if message.responseStatus.isInitialized {
        try self.checkOkStatus(message.responseStatus)
      }
      responseSize = Int(message.responseSize)
    }

    return ServerResponse.Single(
      message: .with {
        $0.payload = .with {
          $0.body = Data(count: responseSize)
        }
      }
    )
  }

  /// Single-sided unbounded streaming from server to client.
  /// The server repeatedly returns a payload with the size requested by the client.
  func streamingFromServer(
    request: ServerRequest.Single<Grpc_Testing_SimpleRequest>
  ) async throws -> ServerResponse.Stream<Grpc_Testing_SimpleResponse> {
    if request.message.responseStatus.isInitialized {
      try self.checkOkStatus(request.message.responseStatus)
    }

    let response = Grpc_Testing_SimpleResponse.with {
      $0.payload = .with {
        $0.body = Data(count: Int(request.message.responseSize))
      }
    }

    return ServerResponse.Stream { writer in
      while self.working.load(ordering: .relaxed) {
        try await writer.write(response)
      }
      return [:]
    }
  }

  /// Two-sided unbounded streaming between server to client.
  /// Both sides send the content of their own choice to the other.
  func streamingBothWays(
    request: ServerRequest.Stream<Grpc_Testing_SimpleRequest>
  ) async throws -> ServerResponse.Stream<Grpc_Testing_SimpleResponse> {
    // The 100 size is used by the other implementations as well.
    // We are using the same canned response size for all responses
    // as it is allowed by the spec.
    let response = Grpc_Testing_SimpleResponse.with {
      $0.payload = .with {
        $0.body = Data(count: 100)
      }
    }

    // Marks if the inbound streaming is ongoing or finished.
    let inboundStreaming = ManagedAtomic<Bool>(true)

    return ServerResponse.Stream { writer in
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          for try await message in request.messages {
            if message.responseStatus.isInitialized {
              try self.checkOkStatus(message.responseStatus)
            }
          }
          inboundStreaming.store(false, ordering: .relaxed)
        }

        group.addTask {
          while inboundStreaming.load(ordering: .relaxed)
            && self.working.load(ordering: .acquiring)
          {
            try await writer.write(response)
          }
        }

        try await group.next()
        group.cancelAll()
        return [:]
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension BenchmarkService {
  private func checkOkStatus(_ responseStatus: Grpc_Testing_EchoStatus) throws {
    guard let code = Status.Code(rawValue: Int(responseStatus.code)) else {
      throw RPCError(code: .invalidArgument, message: "The response status code is invalid.")
    }
    if let code = RPCError.Code(code) {
      throw RPCError(code: code, message: responseStatus.message)
    }
  }
}
