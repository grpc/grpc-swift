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

import GRPCCore

import struct Foundation.Data

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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct EmptyUnary: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    try await testServiceClient.emptyCall(
      request: ClientRequest.Single(message: Grpc_Testing_Empty())
    ) { response in
      try assertEqual(response.message, Grpc_Testing_Empty())
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct LargeUnary: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    let request = Grpc_Testing_SimpleRequest.with { request in
      request.responseSize = 314_159
      request.payload = Grpc_Testing_Payload.with {
        $0.body = Data(count: 271_828)
      }
    }
    try await testServiceClient.unaryCall(
      request: ClientRequest.Single(message: request)
    ) { response in
      try assertEqual(
        response.message.payload,
        Grpc_Testing_Payload.with {
          $0.body = Data(count: 314_159)
        }
      )
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ClientStreaming: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    let request = ClientRequest.Stream { writer in
      for bytes in [27182, 8, 1828, 45904] {
        let message = Grpc_Testing_StreamingInputCallRequest.with {
          $0.payload = Grpc_Testing_Payload.with {
            $0.body = Data(count: bytes)
          }
        }
        try await writer.write(message)
      }
    }

    try await testServiceClient.streamingInputCall(request: request) { response in
      try assertEqual(response.message.aggregatedPayloadSize, 74922)
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ServerStreaming: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    let responseSizes = [31415, 9, 2653, 58979]
    let request = Grpc_Testing_StreamingOutputCallRequest.with { request in
      request.responseParameters = responseSizes.map {
        var parameter = Grpc_Testing_ResponseParameters()
        parameter.size = Int32($0)
        return parameter
      }
    }

    try await testServiceClient.streamingOutputCall(
      request: ClientRequest.Single(message: request)
    ) { response in
      var responseParts = response.messages.makeAsyncIterator()
      // There are 4 response sizes, so if there isn't a message for each one,
      // it means that the client didn't receive 4 messages back.
      for responseSize in responseSizes {
        if let message = try await responseParts.next() {
          try assertEqual(message.payload.body.count, responseSize)
        } else {
          throw AssertionFailure(
            message: "There were less than four responses received."
          )
        }
      }
      // Check that there were not more than 4 responses from the server.
      try assertEqual(try await responseParts.next(), nil)
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct PingPong: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    let ids = AsyncStream.makeStream(of: Int.self)

    let request = ClientRequest.Stream { writer in
      let sizes = [(31_415, 27_182), (9, 8), (2_653, 1_828), (58_979, 45_904)]
      for try await id in ids.stream {
        var message = Grpc_Testing_StreamingOutputCallRequest()
        switch id {
        case 1 ... 4:
          let (responseSize, bodySize) = sizes[id - 1]
          message.responseParameters = [
            Grpc_Testing_ResponseParameters.with {
              $0.size = Int32(responseSize)
            }
          ]
          message.payload = Grpc_Testing_Payload.with {
            $0.body = Data(count: bodySize)
          }
        default:
          // When the id is higher than 4 it means the client received all the expected responses
          // and it doesn't need to send another message.
          return
        }
        try await writer.write(message)
      }
    }
    ids.continuation.yield(1)
    try await testServiceClient.fullDuplexCall(request: request) { response in
      var id = 1
      for try await message in response.messages {
        switch id {
        case 1:
          try assertEqual(message.payload.body, Data(count: 31_415))
        case 2:
          try assertEqual(message.payload.body, Data(count: 9))
        case 3:
          try assertEqual(message.payload.body, Data(count: 2_653))
        case 4:
          try assertEqual(message.payload.body, Data(count: 58_979))
        default:
          throw AssertionFailure(
            message: "We should only receive messages with ids between 1 and 4."
          )
        }

        // Add the next id to the continuation.
        id += 1
        ids.continuation.yield(id)
      }
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct EmptyStream: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    let request = ClientRequest.Stream<Grpc_Testing_StreamingOutputCallRequest> { _ in }

    try await testServiceClient.fullDuplexCall(request: request) { response in
      var messages = response.messages.makeAsyncIterator()
      try await assertEqual(messages.next(), nil)
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct CustomMetadata: InteroperabilityTest {
  let initialMetadataName = "x-grpc-test-echo-initial"
  let initialMetadataValue = "test_initial_metadata_value"

  let trailingMetadataName = "x-grpc-test-echo-trailing-bin"
  let trailingMetadataValue: [UInt8] = [0xAB, 0xAB, 0xAB]

  func checkInitialMetadata(_ metadata: Metadata) throws {
    let values = metadata[self.initialMetadataName]
    try assertEqual(Array(values), [.string(self.initialMetadataValue)])
  }

  func checkTrailingMetadata(_ metadata: Metadata) throws {
    let values = metadata[self.trailingMetadataName]
    try assertEqual(Array(values), [.binary(self.trailingMetadataValue)])
  }

  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)

    let unaryRequest = Grpc_Testing_SimpleRequest.with { request in
      request.responseSize = 314_159
      request.payload = Grpc_Testing_Payload.with {
        $0.body = Data(count: 271_828)
      }
    }
    let metadata: Metadata = [
      self.initialMetadataName: .string(self.initialMetadataValue),
      self.trailingMetadataName: .binary(self.trailingMetadataValue),
    ]

    try await testServiceClient.unaryCall(
      request: ClientRequest.Single(message: unaryRequest, metadata: metadata)
    ) { response in
      // Check the initial metadata.
      let receivedInitialMetadata = response.metadata
      try checkInitialMetadata(receivedInitialMetadata)

      // Check the message.
      try assertEqual(response.message.payload.body, Data(count: 314_159))

      // Check the trailing metadata.
      try checkTrailingMetadata(response.trailingMetadata)
    }

    let streamingRequest = ClientRequest.Stream(metadata: metadata) { writer in
      let message = Grpc_Testing_StreamingOutputCallRequest.with {
        $0.responseParameters = [
          Grpc_Testing_ResponseParameters.with {
            $0.size = 314_159
          }
        ]
        $0.payload = Grpc_Testing_Payload.with {
          $0.body = Data(count: 271_828)
        }
      }
      try await writer.write(message)
    }

    try await testServiceClient.fullDuplexCall(request: streamingRequest) { response in
      switch response.accepted {
      case .success(let contents):
        // Check the initial metadata.
        let receivedInitialMetadata = response.metadata
        try self.checkInitialMetadata(receivedInitialMetadata)

        let parts = try await contents.bodyParts.reduce(into: []) { $0.append($1) }
        try assertEqual(parts.count, 2)

        for part in parts {
          switch part {
          // Check the message.
          case .message(let message):
            try assertEqual(message.payload.body, Data(count: 314_159))
          // Check the trailing metadata.
          case .trailingMetadata(let receivedTrailingMetadata):
            try self.checkTrailingMetadata(receivedTrailingMetadata)
          }
        }
      case .failure(_):
        throw AssertionFailure(
          message: "The client should have received a response from the server."
        )
      }
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct StatusCodeAndMessage: InteroperabilityTest {
  let expectedCode = 2
  let expectedMessage = "test status message"

  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)

    let message = Grpc_Testing_SimpleRequest.with {
      $0.responseStatus = Grpc_Testing_EchoStatus.with {
        $0.code = Int32(self.expectedCode)
        $0.message = self.expectedMessage
      }
    }

    try await testServiceClient.unaryCall(
      request: ClientRequest.Single(message: message)
    ) { response in
      switch response.accepted {
      case .failure(let error):
        try assertEqual(error.code.rawValue, self.expectedCode)
        try assertEqual(error.message, self.expectedMessage)
      case .success(_):
        throw AssertionFailure(
          message:
            "The client should receive an error with the status code and message sent by the client."
        )
      }
    }

    let request = ClientRequest.Stream { writer in
      let message = Grpc_Testing_StreamingOutputCallRequest.with {
        $0.responseStatus = Grpc_Testing_EchoStatus.with {
          $0.code = Int32(self.expectedCode)
          $0.message = self.expectedMessage
        }
      }
      try await writer.write(message)
    }

    try await testServiceClient.fullDuplexCall(request: request) { response in
      do {
        for try await _ in response.messages {
          throw AssertionFailure(
            message:
              "The client should receive an error with the status code and message sent by the client."
          )
        }
      } catch let error as RPCError {
        try assertEqual(error.code.rawValue, self.expectedCode)
        try assertEqual(error.message, self.expectedMessage)
      }
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct SpecialStatusMessage: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)

    let responseMessage = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"
    let message = Grpc_Testing_SimpleRequest.with {
      $0.responseStatus = Grpc_Testing_EchoStatus.with {
        $0.code = 2
        $0.message = responseMessage
      }
    }
    try await testServiceClient.unaryCall(
      request: ClientRequest.Single(message: message)
    ) { response in
      switch response.accepted {
      case .success(_):
        throw AssertionFailure(
          message: "The response should be an error with the error code 2."
        )
      case .failure(let error):
        try assertEqual(error.code.rawValue, 2)
        try assertEqual(error.message, responseMessage)
      }
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct UnimplementedMethod: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let testServiceClient = Grpc_Testing_TestService.Client(client: client)
    try await testServiceClient.unimplementedCall(
      request: ClientRequest.Single(message: Grpc_Testing_Empty())
    ) { response in
      let result = response.accepted
      switch result {
      case .success(_):
        throw AssertionFailure(
          message: "The result should be an error."
        )
      case .failure(let error):
        try assertEqual(error.code, .unimplemented)
      }
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct UnimplementedService: InteroperabilityTest {
  func run(client: GRPCClient) async throws {
    let unimplementedServiceClient = Grpc_Testing_UnimplementedService.Client(client: client)
    try await unimplementedServiceClient.unimplementedCall(
      request: ClientRequest.Single(message: Grpc_Testing_Empty())
    ) { response in
      let result = response.accepted
      switch result {
      case .success(_):
        throw AssertionFailure(
          message: "The result should be an error."
        )
      case .failure(let error):
        try assertEqual(error.code, .unimplemented)
      }
    }
  }
}
