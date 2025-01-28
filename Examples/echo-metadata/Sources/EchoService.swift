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
    let responseMetadata = Metadata(request.metadata.filter({ $0.key.starts(with: "echo-") }))
    return ServerResponse(
      message: .with { $0.text = request.message.text },
      metadata: responseMetadata,
      trailingMetadata: responseMetadata
    )
  }

  func collect(
    request: StreamingServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> ServerResponse<Echo_EchoResponse> {
    let responseMetadata = Metadata(request.metadata.filter({ $0.key.starts(with: "echo-") }))
    let messages = try await request.messages.reduce(into: []) { $0.append($1.text) }
    let joined = messages.joined(separator: " ")

    return ServerResponse(
      message: .with { $0.text = joined },
      metadata: responseMetadata,
      trailingMetadata: responseMetadata
    )
  }

  func expand(
    request: ServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Echo_EchoResponse> {
    let responseMetadata = Metadata(request.metadata.filter({ $0.key.starts(with: "echo-") }))
    let parts = request.message.text.split(separator: " ")
    let messages = parts.map { part in Echo_EchoResponse.with { $0.text = String(part) } }

    return StreamingServerResponse(metadata: responseMetadata) { writer in
      try await writer.write(contentsOf: messages)
      return responseMetadata
    }
  }

  func update(
    request: StreamingServerRequest<Echo_EchoRequest>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Echo_EchoResponse> {
    let responseMetadata = Metadata(request.metadata.filter({ $0.key.starts(with: "echo-") }))
    return StreamingServerResponse(metadata: responseMetadata) { writer in
      for try await message in request.messages {
        try await writer.write(.with { $0.text = message.text })
      }
      return responseMetadata
    }
  }
}
