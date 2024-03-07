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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public protocol InteroperabilityTest {
  /// Run a test case using the given connection.
  ///
  /// The test case is considered unsuccessful if any exception is thrown, conversely if no
  /// exceptions are thrown it is successful.
  ///
  /// - Parameter client: The client to use for the test.
  /// - Throws: Any exception may be thrown to indicate an unsuccessful test.
  func run(client: GRPCClient) async throws
}

/// Test cases as listed by the [gRPC interoperability test description
/// specification](https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md).
///
/// This is not a complete list, the following tests have not been implemented:
/// - cacheable_unary
/// - client-compressed-unary
/// - server-compressed-unary
/// - client_compressed_streaming
/// - server_compressed_streaming
/// - compute_engine_creds
/// - jwt_token_creds
/// - oauth2_auth_token
/// - per_rpc_creds
/// - google_default_credentials
/// - compute_engine_channel_credentials
/// - cancel_after_begin
/// - cancel_after_first_response
///
/// Note: Tests for compression have not been implemented yet as compression is
/// not supported. Once the API which allows for compression will be implemented
/// these tests should be added.
public enum InteroperabilityTestCase: String, CaseIterable {
  case emptyUnary = "empty_unary"
  case largeUnary = "large_unary"
  case clientStreaming = "client_streaming"
  case serverStreaming = "server_streaming"
  case pingPong = "ping_pong"
  case emptyStream = "empty_stream"
  case customMetadata = "custom_metadata"
  case statusCodeAndMessage = "status_code_and_message"
  case specialStatusMessage = "special_status_message"
  case unimplementedMethod = "unimplemented_method"
  case unimplementedService = "unimplemented_service"

  public var name: String {
    return self.rawValue
  }
}

@available(macOS 13.0, *)
extension InteroperabilityTestCase {
  /// Return a new instance of the test case.
  public func makeTest() -> InteroperabilityTest {
    switch self {
    case .emptyUnary:
      return EmptyUnary()
    case .largeUnary:
      return LargeUnary()
    case .clientStreaming:
      return ClientStreaming()
    case .serverStreaming:
      return ServerStreaming()
    case .pingPong:
      return PingPong()
    case .emptyStream:
      return EmptyStream()
    case .customMetadata:
      return CustomMetadata()
    case .statusCodeAndMessage:
      return StatusCodeAndMessage()
    case .specialStatusMessage:
      return SpecialStatusMessage()
    case .unimplementedMethod:
      return UnimplementedMethod()
    case .unimplementedService:
      return UnimplementedService()
    }
  }
}
