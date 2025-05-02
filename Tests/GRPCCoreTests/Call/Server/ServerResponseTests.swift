/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import Testing

@Suite("ServerResponse")
struct ServerResponseTests {
  @Test("ServerResponse(message:metadata:trailingMetadata:)")
  func responseInitSuccess() throws {
    let response = ServerResponse(
      message: "message",
      metadata: ["metadata": "initial"],
      trailingMetadata: ["metadata": "trailing"]
    )

    let contents = try response.accepted.get()
    #expect(contents.message == "message")
    #expect(contents.metadata == ["metadata": "initial"])
    #expect(contents.trailingMetadata == ["metadata": "trailing"])
  }

  @Test("ServerResponse(of:error:)")
  func responseInitError() throws {
    let error = RPCError(code: .aborted, message: "Aborted")
    let response = ServerResponse(of: String.self, error: error)
    switch response.accepted {
    case .success:
      Issue.record("Expected error")
    case .failure(let rpcError):
      #expect(rpcError == error)
    }
  }

  @Test("StreamingServerResponse(of:metadata:producer:)")
  func streamingResponseInitSuccess() async throws {
    let response = StreamingServerResponse(
      of: String.self,
      metadata: ["metadata": "initial"]
    ) { _ in
      // Empty body.
      return ["metadata": "trailing"]
    }

    let contents = try response.accepted.get()
    #expect(contents.metadata == ["metadata": "initial"])
    let trailingMetadata = try await contents.producer(.failTestOnWrite())
    #expect(trailingMetadata == ["metadata": "trailing"])
  }

  @Test("StreamingServerResponse(of:error:)")
  func streamingResponseInitError() async throws {
    let error = RPCError(code: .aborted, message: "Aborted")
    let response = StreamingServerResponse(of: String.self, error: error)
    switch response.accepted {
    case .success:
      Issue.record("Expected error")
    case .failure(let rpcError):
      #expect(rpcError == error)
    }
  }

  @Test("StreamingServerResponse(single:) (accepted)")
  func singleToStreamConversionForSuccessfulResponse() async throws {
    let single = ServerResponse(
      message: "foo",
      metadata: ["metadata": "initial"],
      trailingMetadata: ["metadata": "trailing"]
    )

    let stream = StreamingServerResponse(single: single)
    let (messages, continuation) = AsyncStream.makeStream(of: String.self)
    let trailingMetadata: Metadata

    switch stream.accepted {
    case .success(let contents):
      trailingMetadata = try await contents.producer(.gathering(into: continuation))
      continuation.finish()
    case .failure(let error):
      throw error
    }

    #expect(stream.metadata == ["metadata": "initial"])
    let collected = try await messages.collect()
    #expect(collected == ["foo"])
    #expect(trailingMetadata == ["metadata": "trailing"])
  }

  @Test("StreamingServerResponse(single:) (rejected)")
  func singleToStreamConversionForFailedResponse() async throws {
    let error = RPCError(code: .aborted, message: "aborted")
    let single = ServerResponse(of: String.self, error: error)
    let stream = StreamingServerResponse(single: single)

    switch stream.accepted {
    case .success:
      Issue.record("Expected error")
    case .failure(let rpcError):
      #expect(rpcError == error)
    }
  }

  @Test("Mutate metadata on response", arguments: [true, false])
  func mutateMetadataOnResponse(accepted: Bool) {
    var response: ServerResponse<String>
    if accepted {
      response = ServerResponse(message: "")
    } else {
      response = ServerResponse(error: RPCError(code: .aborted, message: ""))
    }

    response.metadata.addString("value", forKey: "key")
    #expect(response.metadata == ["key": "value"])
  }

  @Test("Mutate metadata on streaming response", arguments: [true, false])
  func mutateMetadataOnStreamingResponse(accepted: Bool) {
    var response: StreamingServerResponse<String>
    if accepted {
      response = StreamingServerResponse { _ in [:] }
    } else {
      response = StreamingServerResponse(error: RPCError(code: .aborted, message: ""))
    }

    response.metadata.addString("value", forKey: "key")
    #expect(response.metadata == ["key": "value"])
  }
}
