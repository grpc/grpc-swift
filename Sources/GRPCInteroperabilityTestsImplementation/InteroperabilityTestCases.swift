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
import Foundation
import GRPC
import GRPCInteroperabilityTestModels
import NIOHTTP1
import NIOHPACK

/// This test verifies that implementations support zero-size messages. Ideally, client
/// implementations would verify that the request and response were zero bytes serialized, but
/// this is generally prohibitive to perform, so is not required.
///
/// Server features:
/// - EmptyCall
///
/// Procedure:
/// 1. Client calls EmptyCall with the default Empty message
///
/// Client asserts:
/// - call was successful
/// - response is non-null
class EmptyUnary: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)
    let call = client.emptyCall(Grpc_Testing_Empty())

    try waitAndAssertEqual(call.response, Grpc_Testing_Empty())
    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
  }
}

/// This test verifies that gRPC requests marked as cacheable use GET verb instead of POST, and
/// that server sets appropriate cache control headers for the response to be cached by a proxy.
/// This test requires that the server is behind a caching proxy. Use of current timestamp in the
/// request prevents accidental cache matches left over from previous tests.
///
/// Server features:
/// - CacheableUnaryCall
///
/// Procedure:
/// 1. Client calls CacheableUnaryCall with SimpleRequest request with payload set to current
///    timestamp. Timestamp format is irrelevant, and resolution is in nanoseconds. Client adds a
///    x-user-ip header with value 1.2.3.4 to the request. This is done since some proxys such as
///    GFE will not cache requests from localhost. Client marks the request as cacheable by
///    setting the cacheable flag in the request context. Longer term this should be driven by
///    the method option specified in the proto file itself.
/// 2. Client calls CacheableUnaryCall again immediately with the same request and configuration
///    as the previous call.
///
/// Client asserts:
/// - Both calls were successful
/// - The payload body of both responses is the same.
class CacheableUnary: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    var timestamp = DispatchTime.now().rawValue
    let request = Grpc_Testing_SimpleRequest.withPayload(of: .bytes(of: &timestamp))

    let headers: HPACKHeaders = ["x-user-ip": "1.2.3.4"]
    let callOptions = CallOptions(customMetadata: headers, cacheable: true)

    let call1 = client.cacheableUnaryCall(request, callOptions: callOptions)
    let call2 = client.cacheableUnaryCall(request, callOptions: callOptions)

    // The server ignores the request payload so we must not validate against it.
    try waitAndAssertEqual(call1.response.map { $0.payload }, call2.response.map { $0.payload })
    try waitAndAssertEqual(call1.status.map { $0.code }, .ok)
    try waitAndAssertEqual(call2.status.map { $0.code }, .ok)
  }
}

/// This test verifies unary calls succeed in sending messages, and touches on flow control (even
/// if compression is enabled on the channel).
///
/// Server features:
/// - UnaryCall
///
/// Procedure:
/// 1. Client calls UnaryCall with:
///    ```
///    {
///        response_size: 314159
///        payload:{
///            body: 271828 bytes of zeros
///        }
///    }
///    ```
///
/// Client asserts:
/// - call was successful
/// - response payload body is 314159 bytes in size
/// - clients are free to assert that the response payload body contents are zero and comparing
///   the entire response message against a golden response
class LargeUnary: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let request = Grpc_Testing_SimpleRequest.with { request in
      request.responseSize = 314_159
      request.payload = .zeros(count: 271_828)
    }

    let call = client.unaryCall(request)

    try waitAndAssertEqual(call.response.map { $0.payload }, .zeros(count: 314_159))
    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
  }
}

/// This test verifies the client can compress unary messages by sending two unary calls, for
/// compressed and uncompressed payloads. It also sends an initial probing request to verify
/// whether the server supports the CompressedRequest feature by checking if the probing call
/// fails with an `INVALID_ARGUMENT` status.
///
/// Server features:
/// - UnaryCall
/// - CompressedRequest
///
/// Procedure:
/// 1. Client calls UnaryCall with the feature probe, an *uncompressed* message:
///    ```
///    {
///      expect_compressed:{
///        value: true
///      }
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
/// 2. Client calls UnaryCall with the *compressed* message:
///    ```
///    {
///      expect_compressed:{
///        value: true
///      }
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
/// 3. Client calls UnaryCall with the *uncompressed* message:
///    ```
///    {
///      expect_compressed:{
///        value: false
///      }
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
///
/// Client asserts:
/// - First call failed with `INVALID_ARGUMENT` status.
/// - Subsequent calls were successful.
/// - Response payload body is 314159 bytes in size.
/// - Clients are free to assert that the response payload body contents are zeros and comparing the
///   entire response message against a golden response.
class ClientCompressedUnary: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let compressedRequest = Grpc_Testing_SimpleRequest.with { request in
      request.expectCompressed = true
      request.responseSize = 314_159
      request.payload = .zeros(count: 271_828)
    }

    var uncompressedRequest = compressedRequest
    uncompressedRequest.expectCompressed = false

    // For unary RPCs we disable compression at the call level.

    // With compression expected but *disabled*.
    let probe = client.unaryCall(compressedRequest)
    try waitAndAssertEqual(probe.status.map { $0.code }, .invalidArgument)

    // With compression expected and enabled.
    let options = CallOptions(messageEncoding: .enabled(.init(forRequests: .gzip, decompressionLimit: .absolute(1024 * 1024))))
    let compressed = client.unaryCall(compressedRequest, callOptions: options)
    try waitAndAssertEqual(compressed.response.map { $0.payload }, .zeros(count: 314_159))
    try waitAndAssertEqual(compressed.status.map { $0.code }, .ok)

    // With compression not expected and disabled.
    let uncompressed = client.unaryCall(uncompressedRequest)
    try waitAndAssertEqual(uncompressed.response.map { $0.payload }, .zeros(count: 314_159))
    try waitAndAssertEqual(uncompressed.status.map { $0.code }, .ok)
  }
}

/// This test verifies the server can compress unary messages. It sends two unary
/// requests, expecting the server's response to be compressed or not according to
/// the `response_compressed` boolean.
///
/// Whether compression was actually performed is determined by the compression bit
/// in the response's message flags. *Note that some languages may not have access
/// to the message flags, in which case the client will be unable to verify that
/// the `response_compressed` boolean is obeyed by the server*.
///
///
/// Server features:
/// - UnaryCall
/// - CompressedResponse
///
/// Procedure:
/// 1. Client calls UnaryCall with `SimpleRequest`:
///    ```
///    {
///      response_compressed:{
///        value: true
///      }
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
///    ```
///    {
///      response_compressed:{
///        value: false
///      }
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
///
/// Client asserts:
/// - call was successful
/// - if supported by the implementation, when `response_compressed` is true, the response MUST have
///   the compressed message flag set.
/// - if supported by the implementation, when `response_compressed` is false, the response MUST NOT
///   have the compressed message flag set.
/// - response payload body is 314159 bytes in size in both cases.
/// - clients are free to assert that the response payload body contents are zero and comparing the
///   entire response message against a golden response
class ServerCompressedUnary: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let compressedRequest = Grpc_Testing_SimpleRequest.with { request in
      request.responseCompressed = true
      request.responseSize = 314_159
      request.payload = .zeros(count: 271_828)
    }

    let options = CallOptions(messageEncoding: .enabled(.responsesOnly(decompressionLimit: .absolute(1024 * 1024))))
    let compressed = client.unaryCall(compressedRequest, callOptions: options)
    // We can't verify that the compression bit was set, instead we verify that the encoding header
    // was sent by the server. This isn't quite the same since as it can still be set but the
    // compression may be not set.
    try waitAndAssert(compressed.initialMetadata) { headers in
      return headers.first(name: "grpc-encoding") != nil
    }
    try waitAndAssertEqual(compressed.response.map { $0.payload }, .zeros(count: 314_159))
    try waitAndAssertEqual(compressed.status.map { $0.code }, .ok)

    var uncompressedRequest = compressedRequest
    uncompressedRequest.responseCompressed.value = false
    let uncompressed = client.unaryCall(uncompressedRequest)
    // We can't check even check for the 'grpc-encoding' header here since it could be set with the
    // compression bit on the message not set.
    try waitAndAssertEqual(uncompressed.response.map { $0.payload }, .zeros(count: 314_159))
    try waitAndAssertEqual(uncompressed.status.map { $0.code }, .ok)
  }
}

/// This test verifies that client-only streaming succeeds.
///
/// Server features:
/// - StreamingInputCall
///
/// Procedure:
/// 1. Client calls StreamingInputCall
/// 2. Client sends:
///    ```
///    {
///        payload:{
///            body: 27182 bytes of zeros
///        }
///    }
///    ```
/// 3. Client then sends:
///    ```
///    {
///        payload:{
///            body: 8 bytes of zeros
///        }
///    }
///    ```
/// 4. Client then sends:
///    ```
///    {
///        payload:{
///            body: 1828 bytes of zeros
///        }
///    }
///    ```
/// 5. Client then sends:
///    ```
///    {
///        payload:{
///            body: 45904 bytes of zeros
///        }
///    }
///    ```
/// 6. Client half-closes
///
/// Client asserts:
/// - call was successful
/// - response aggregated_payload_size is 74922
class ClientStreaming: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)
    let call = client.streamingInputCall()

    let requests = [27_182, 8, 1_828, 45_904].map { zeros in
      Grpc_Testing_StreamingInputCallRequest.withPayload(of: .zeros(count: zeros))
    }
    call.sendMessages(requests, promise: nil)
    call.sendEnd(promise: nil)

    try waitAndAssertEqual(call.response.map { $0.aggregatedPayloadSize }, 74_922)
    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
  }
}

/// This test verifies the client can compress requests on per-message basis by performing a
/// two-request streaming call. It also sends an initial probing request to verify whether the
/// server supports the `CompressedRequest` feature by checking if the probing call fails with
/// an `INVALID_ARGUMENT` status.
///
/// Procedure:
///  1. Client calls `StreamingInputCall` and sends the following feature-probing
///     *uncompressed* `StreamingInputCallRequest` message
///
///     ```
///     {
///       expect_compressed:{
///         value: true
///       }
///       payload:{
///         body: 27182 bytes of zeros
///       }
///     }
///     ```
///     If the call does not fail with `INVALID_ARGUMENT`, the test fails.
///     Otherwise, we continue.
///
///  2. Client calls `StreamingInputCall` again, sending the *compressed* message
///
///     ```
///     {
///       expect_compressed:{
///         value: true
///       }
///       payload:{
///         body: 27182 bytes of zeros
///       }
///     }
///     ```
///
///  3. And finally, the *uncompressed* message
///     ```
///     {
///       expect_compressed:{
///         value: false
///       }
///       payload:{
///         body: 45904 bytes of zeros
///       }
///     }
///     ```
///
///  4. Client half-closes
///
/// Client asserts:
/// - First call fails with `INVALID_ARGUMENT`.
/// - Next calls succeeds.
/// - Response aggregated payload size is 73086.
class ClientCompressedStreaming: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    // Does the server support this test? To find out we need to send an uncompressed probe. However
    // we need to disable compression at the RPC level as we don't have access to whether the
    // compression byte is set on messages. As such the corresponding code in the service
    // implementation checks against the 'grpc-encoding' header as a best guess. Disabling
    // compression here will stop that header from being sent.
    let probe = client.streamingInputCall()
    let probeRequest: Grpc_Testing_StreamingInputCallRequest = .with { request in
      request.expectCompressed = true
      request.payload = .zeros(count: 27_182)
    }

    // Compression is disabled at the RPC level.
    probe.sendMessage(probeRequest, promise: nil)
    probe.sendEnd(promise: nil)

    // We *expect* invalid argument here. If not then the server doesn't support this test.
    try waitAndAssertEqual(probe.status.map { $0.code }, .invalidArgument)

    // Now for the actual test.

    // The first message is identical to the probe message, we'll reuse that.
    // The second should not be compressed.
    let secondMessage: Grpc_Testing_StreamingInputCallRequest = .with { request in
      request.expectCompressed = false
      request.payload = .zeros(count: 45_904)
    }

    let options = CallOptions(messageEncoding: .enabled(.init(forRequests: .gzip, decompressionLimit: .ratio(10))))
    let streaming = client.streamingInputCall(callOptions: options)
    streaming.sendMessage(probeRequest, compression: .enabled, promise: nil)
    streaming.sendMessage(secondMessage, compression: .disabled, promise: nil)
    streaming.sendEnd(promise: nil)

    try waitAndAssertEqual(streaming.response.map { $0.aggregatedPayloadSize }, 73_086)
    try waitAndAssertEqual(streaming.status.map { $0.code }, .ok)
  }
}

/// This test verifies that server-only streaming succeeds.
///
/// Server features:
/// - StreamingOutputCall
///
/// Procedure:
/// 1. Client calls StreamingOutputCall with StreamingOutputCallRequest:
///    ```
///    {
///        response_parameters:{
///            size: 31415
///        }
///        response_parameters:{
///            size: 9
///        }
///        response_parameters:{
///            size: 2653
///        }
///        response_parameters:{
///            size: 58979
///        }
///    }
///    ```
///
/// Client asserts:
/// - call was successful
/// - exactly four responses
/// - response payload bodies are sized (in order): 31415, 9, 2653, 58979
/// - clients are free to assert that the response payload body contents are zero and
///   comparing the entire response messages against golden responses
class ServerStreaming: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let responseSizes = [31_415, 9, 2_653, 58_979]
    let request = Grpc_Testing_StreamingOutputCallRequest.with { request in
      request.responseParameters = responseSizes.map { .size($0) }
    }

    var payloads: [Grpc_Testing_Payload] = []
    let call = client.streamingOutputCall(request) { response in
      payloads.append(response.payload)
    }

    // Wait for the status first to ensure we've finished collecting responses.
    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
    try assertEqual(payloads, responseSizes.map { .zeros(count: $0) })
  }
}

/// This test verifies that the server can compress streaming messages and disable compression on
/// individual messages, expecting the server's response to be compressed or not according to the
/// `response_compressed` boolean.
///
/// Whether compression was actually performed is determined by the compression bit in the
/// response's message flags. *Note that some languages may not have access to the message flags, in
/// which case the client will be unable to verify that the `response_compressed` boolean is obeyed
/// by the server*.
///
/// Server features:
/// - StreamingOutputCall
/// - CompressedResponse
///
/// Procedure:
///  1. Client calls StreamingOutputCall with `StreamingOutputCallRequest`:
///     ```
///     {
///       response_parameters:{
///         compressed: {
///           value: true
///         }
///         size: 31415
///       }
///       response_parameters:{
///         compressed: {
///           value: false
///         }
///         size: 92653
///       }
///     }
///     ```
///
/// Client asserts:
/// - call was successful
/// - exactly two responses
/// - if supported by the implementation, when `response_compressed` is false, the response's
///   messages MUST NOT have the compressed message flag set.
/// - if supported by the implementation, when `response_compressed` is true, the response's
///   messages MUST have the compressed message flag set.
/// - response payload bodies are sized (in order): 31415, 92653
/// - clients are free to assert that the response payload body contents are zero and comparing the
///   entire response messages against golden responses
class ServerCompressedStreaming: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let request: Grpc_Testing_StreamingOutputCallRequest = .with { request in
      request.responseParameters = [
        .with {
          $0.compressed = true
          $0.size = 31_415
        },
        .with {
          $0.compressed = false
          $0.size = 92_653
        }
      ]
    }

    let options = CallOptions(messageEncoding: .enabled(.responsesOnly(decompressionLimit: .absolute(1024 * 1024))))
    var payloads: [Grpc_Testing_Payload] = []
    let rpc = client.streamingOutputCall(request, callOptions: options) { response in
      payloads.append(response.payload)
    }

    // We can't verify that the compression bit was set, instead we verify that the encoding header
    // was sent by the server. This isn't quite the same since as it can still be set but the
    // compression may be not set.
    try waitAndAssert(rpc.initialMetadata) { headers in
      return headers.first(name: "grpc-encoding") != nil
    }

    let responseSizes = [31_415, 92_653]
    // Wait for the status first to ensure we've finished collecting responses.
    try waitAndAssertEqual(rpc.status.map { $0.code }, .ok)
    try assertEqual(payloads, responseSizes.map { .zeros(count: $0) })
  }
}

/// This test verifies that full duplex bidi is supported.
///
/// Server features:
/// - FullDuplexCall
///
/// Procedure:
/// 1. Client calls FullDuplexCall with:
///    ```
///    {
///        response_parameters:{
///            size: 31415
///        }
///        payload:{
///            body: 27182 bytes of zeros
///        }
///    }
///    ```
/// 2. After getting a reply, it sends:
///    ```
///    {
///        response_parameters:{
///            size: 9
///        }
///        payload:{
///            body: 8 bytes of zeros
///        }
///    }
///    ```
/// 3. After getting a reply, it sends:
///    ```
///    {
///        response_parameters:{
///            size: 2653
///        }
///        payload:{
///            body: 1828 bytes of zeros
///        }
///    }
///    ```
/// 4. After getting a reply, it sends:
///    ```
///    {
///        response_parameters:{
///            size: 58979
///        }
///        payload:{
///            body: 45904 bytes of zeros
///        }
///    }
///    ```
/// 5. After getting a reply, client half-closes
///
/// Client asserts:
/// - call was successful
/// - exactly four responses
/// - response payload bodies are sized (in order): 31415, 9, 2653, 58979
/// - clients are free to assert that the response payload body contents are zero and
///   comparing the entire response messages against golden responses
class PingPong: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let requestSizes = [27_182, 8, 1_828, 45_904]
    let responseSizes = [31_415, 9, 2_653, 58_979]

    let responseReceived = DispatchSemaphore(value: 0)

    var payloads: [Grpc_Testing_Payload] = []
    let call = client.fullDuplexCall { response in
      payloads.append(response.payload)
      responseReceived.signal()
    }

    try zip(requestSizes, responseSizes).map { requestSize, responseSize in
      Grpc_Testing_StreamingOutputCallRequest.with { request in
        request.payload = .zeros(count: requestSize)
        request.responseParameters = [.size(responseSize)]
      }
    }.forEach { request in
      call.sendMessage(request, promise: nil)
      try assertEqual(responseReceived.wait(timeout: .now() + .seconds(1)), .success)
    }
    call.sendEnd(promise: nil)

    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
    try assertEqual(payloads, responseSizes.map { .zeros(count: $0) })
  }
}

/// This test verifies that streams support having zero-messages in both directions.
///
/// Server features:
/// - FullDuplexCall
///
/// Procedure:
/// 1. Client calls FullDuplexCall and then half-closes
///
/// Client asserts:
/// - call was successful
/// - exactly zero responses
class EmptyStream: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    var responses: [Grpc_Testing_StreamingOutputCallResponse] = []
    let call = client.fullDuplexCall { response in
      responses.append(response)
    }

    try call.sendEnd().wait()

    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
    try assertEqual(responses, [])
  }
}

/// This test verifies that custom metadata in either binary or ascii format can be sent as
/// initial-metadata by the client and as both initial- and trailing-metadata by the server.
///
/// Server features:
/// - UnaryCall
/// - FullDuplexCall
/// - Echo Metadata
///
/// Procedure:
/// 1. The client attaches custom metadata with the following keys and values
///    to a UnaryCall with request:
///    - key: "x-grpc-test-echo-initial", value: "test_initial_metadata_value"
///    - key: "x-grpc-test-echo-trailing-bin", value: 0xababab
///    ```
///    {
///      response_size: 314159
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
/// 2. The client attaches custom metadata with the following keys and values
///    to a FullDuplexCall with request:
///    - key: "x-grpc-test-echo-initial", value: "test_initial_metadata_value"
///    - key: "x-grpc-test-echo-trailing-bin", value: 0xababab
///    ```
///    {
///      response_parameters:{
///        size: 314159
///      }
///      payload:{
///        body: 271828 bytes of zeros
///      }
///    }
///    ```
///    and then half-closes
///
/// Client asserts:
/// - call was successful
/// - metadata with key "x-grpc-test-echo-initial" and value "test_initial_metadata_value" is
///   received in the initial metadata for calls in Procedure steps 1 and 2.
/// - metadata with key "x-grpc-test-echo-trailing-bin" and value 0xababab is received in the
///   trailing metadata for calls in Procedure steps 1 and 2.
class CustomMetadata: InteroperabilityTest {
  let initialMetadataName = "x-grpc-test-echo-initial"
  let initialMetadataValue = "test_initial_metadata_value"

  let trailingMetadataName = "x-grpc-test-echo-trailing-bin"
  let trailingMetadataValue = Data([0xab, 0xab, 0xab]).base64EncodedString()

  func checkMetadata<SpecificClientCall>(call: SpecificClientCall) throws where SpecificClientCall: ClientCall {
    let initialName = call.initialMetadata.map { $0[self.initialMetadataName] }
    try waitAndAssertEqual(initialName, [self.initialMetadataValue])

    let trailingName = call.trailingMetadata.map { $0[self.trailingMetadataName] }
    try waitAndAssertEqual(trailingName, [self.trailingMetadataValue])

    try waitAndAssertEqual(call.status.map { $0.code }, .ok)
  }

  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let unaryRequest = Grpc_Testing_SimpleRequest.with { request in
      request.responseSize = 314_159
      request.payload = .zeros(count: 217_828)
    }

    let customMetadata: HPACKHeaders = [
      self.initialMetadataName: self.initialMetadataValue,
      self.trailingMetadataName: self.trailingMetadataValue
    ]

    let callOptions = CallOptions(customMetadata: customMetadata)

    let unaryCall = client.unaryCall(unaryRequest, callOptions: callOptions)
    try self.checkMetadata(call: unaryCall)

    let duplexCall = client.fullDuplexCall(callOptions: callOptions) { _ in }
    let duplexRequest = Grpc_Testing_StreamingOutputCallRequest.with { request in
      request.responseParameters = [.size(314_159)]
      request.payload = .zeros(count: 271_828)
    }

    duplexCall.sendMessage(duplexRequest, promise: nil)
    duplexCall.sendEnd(promise: nil)

    try self.checkMetadata(call: duplexCall)
  }
}

/// This test verifies unary calls succeed in sending messages, and propagate back status code and
/// message sent along with the messages.
///
/// Server features:
/// - UnaryCall
/// - FullDuplexCall
/// - Echo Status
///
/// Procedure:
/// 1. Client calls UnaryCall with:
///    ```
///    {
///        response_status:{
///            code: 2
///            message: "test status message"
///        }
///    }
///    ```
/// 2. Client calls FullDuplexCall with:
///    ```
///    {
///        response_status:{
///            code: 2
///            message: "test status message"
///        }
///    }
///    ```
/// 3. and then half-closes
///
/// Client asserts:
/// - received status code is the same as the sent code for both Procedure steps 1 and 2
/// - received status message is the same as the sent message for both Procedure steps 1 and 2
class StatusCodeAndMessage: InteroperabilityTest {
  let expectedCode = 2
  let expectedMessage = "test status message"

  func checkStatus<SpecificClientCall>(call: SpecificClientCall) throws where SpecificClientCall: ClientCall {
    try waitAndAssertEqual(call.status.map { $0.code.rawValue }, self.expectedCode)
    try waitAndAssertEqual(call.status.map { $0.message }, self.expectedMessage)
  }

  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let echoStatus = Grpc_Testing_EchoStatus(code: Int32(self.expectedCode), message: self.expectedMessage)

    let unaryCall = client.unaryCall(.withStatus(of: echoStatus))
    try self.checkStatus(call: unaryCall)

    var responses: [Grpc_Testing_StreamingOutputCallResponse] = []
    let duplexCall = client.fullDuplexCall { response in
      responses.append(response)
    }

    duplexCall.sendMessage(.withStatus(of: echoStatus), promise: nil)
    duplexCall.sendEnd(promise: nil)

    try self.checkStatus(call: duplexCall)
    try assertEqual(responses, [])
  }
}

/// This test verifies Unicode and whitespace is correctly processed in status message. "\t" is
/// horizontal tab. "\r" is carriage return. "\n" is line feed.
///
/// Server features:
/// - UnaryCall
/// - Echo Status
///
/// Procedure:
/// 1. Client calls UnaryCall with:
///    ```
///    {
///        response_status:{
///            code: 2
///            message: "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"
///        }
///    }
///    ```
///
/// Client asserts:
/// - received status code is the same as the sent code for Procedure step 1
/// - received status message is the same as the sent message for Procedure step 1, including all
///   whitespace characters
class SpecialStatusMessage: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let code = 2
    let message = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"

    let call = client.unaryCall(.withStatus(of: .init(code: Int32(code), message: message)))
    try waitAndAssertEqual(call.status.map { $0.code.rawValue }, code)
    try waitAndAssertEqual(call.status.map { $0.message }, message)
  }
}

/// This test verifies that calling an unimplemented RPC method returns the UNIMPLEMENTED status
/// code.
///
/// Server features: N/A
///
/// Procedure:
/// 1. Client calls grpc.testing.TestService/UnimplementedCall with an empty request (defined as
///    grpc.testing.Empty):
///    ```
///    {
///    }
///    ```
///
/// Client asserts:
/// - received status code is 12 (UNIMPLEMENTED)
class UnimplementedMethod: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)
    let call = client.unimplementedCall(Grpc_Testing_Empty())
    try waitAndAssertEqual(call.status.map { $0.code }, .unimplemented)
  }
}

/// This test verifies calling an unimplemented server returns the UNIMPLEMENTED status code.
///
/// Server features: N/A
///
/// Procedure:
/// 1. Client calls grpc.testing.UnimplementedService/UnimplementedCall with an empty request
///    (defined as grpc.testing.Empty):
///    ```
///    {
///    }
///    ```
///
/// Client asserts:
/// - received status code is 12 (UNIMPLEMENTED)
class UnimplementedService: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_UnimplementedServiceClient(channel: connection)
    let call = client.unimplementedCall(Grpc_Testing_Empty())
    try waitAndAssertEqual(call.status.map { $0.code }, .unimplemented)
  }
}

/// This test verifies that a request can be cancelled after metadata has been sent but before
/// payloads are sent.
///
/// Server features:
/// - StreamingInputCall
///
/// Procedure:
/// 1. Client starts StreamingInputCall
/// 2. Client immediately cancels request
///
/// Client asserts:
/// - Call completed with status CANCELLED
class CancelAfterBegin: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)
    let call = client.streamingInputCall()
    call.cancel(promise: nil)

    try waitAndAssertEqual(call.status.map { $0.code }, .cancelled)
  }
}

/// This test verifies that a request can be cancelled after receiving a message from the server.
///
/// Server features:
/// - FullDuplexCall
///
/// Procedure:
/// 1. Client starts FullDuplexCall with
///    ```
///    {
///        response_parameters:{
///            size: 31415
///        }
///        payload:{
///            body: 27182 bytes of zeros
///        }
///    }
///    ```
/// 2. After receiving a response, client cancels request
///
/// Client asserts:
/// - Call completed with status CANCELLED
class CancelAfterFirstResponse: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)
    let promise = connection.eventLoop.makePromise(of: Void.self)

    let call = client.fullDuplexCall { _ in
      promise.succeed(())
    }

    promise.futureResult.whenSuccess {
      call.cancel(promise: nil)
    }

    let request = Grpc_Testing_StreamingOutputCallRequest.with { request in
      request.responseParameters = [.size(31_415)]
      request.payload = .zeros(count: 27_182)
    }

    call.sendMessage(request, promise: nil)

    try waitAndAssertEqual(call.status.map { $0.code }, .cancelled)
  }
}

/// This test verifies that an RPC request whose lifetime exceeds its configured timeout value
/// will end with the DeadlineExceeded status.
///
/// Server features:
/// - FullDuplexCall
///
/// Procedure:
/// 1. Client calls FullDuplexCall with the following request and sets its timeout to 1ms
///    ```
///    {
///        payload:{
///            body: 27182 bytes of zeros
///        }
///    }
///    ```
/// 2. Client waits
///
/// Client asserts:
/// - Call completed with status DEADLINE_EXCEEDED.
class TimeoutOnSleepingServer: InteroperabilityTest {
  func run(using connection: ClientConnection) throws {
    let client = Grpc_Testing_TestServiceClient(channel: connection)

    let callOptions = CallOptions(timeout: try .milliseconds(1))
    let call = client.fullDuplexCall(callOptions: callOptions) { _ in }

    try waitAndAssertEqual(call.status.map { $0.code }, .deadlineExceeded)
  }
}
