/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

struct EchoService: Echo_Echo.ServiceProtocol {
  func get(
    request: ServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> ServerResponse<Echo_EchoResponse> {
    let responseMetadata = request.metadata.echoPairs
    return ServerResponse(
      message: .init(),
      metadata: responseMetadata,
      trailingMetadata: responseMetadata
    )
  }

  func collect(
    request: StreamingServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> ServerResponse<Echo_EchoResponse> {
    let responseMetadata = request.metadata.echoPairs
    return ServerResponse(
      message: .init(),
      metadata: responseMetadata,
      trailingMetadata: responseMetadata
    )
  }

  func expand(
    request: ServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Echo_EchoResponse> {
    let responseMetadata = request.metadata.echoPairs
    return StreamingServerResponse(
      single: ServerResponse(
        message: .init(),
        metadata: responseMetadata,
        trailingMetadata: responseMetadata
      )
    )
  }

  func update(
    request: StreamingServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Echo_EchoResponse> {
    for try await _ in request.messages {
      // Wait for request to be done
    }

    let responseMetadata = request.metadata.echoPairs
    return StreamingServerResponse(
      single: ServerResponse(
        message: .init(),
        metadata: responseMetadata,
        trailingMetadata: responseMetadata
      )
    )
  }
}
