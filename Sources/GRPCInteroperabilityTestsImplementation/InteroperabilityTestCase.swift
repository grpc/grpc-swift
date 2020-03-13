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
import NIO
import NIOHTTP1

public protocol InteroperabilityTest {
  /// Run a test case using the given connection.
  ///
  /// The test case is considered unsuccessful if any exception is thrown, conversely if no
  /// exceptions are thrown it is successful.
  ///
  /// - Parameter connection: The connection to use for the test.
  /// - Throws: Any exception may be thrown to indicate an unsuccessful test.
  func run(using connection: ClientConnection) throws

  /// Configure the connection from a set of defaults using to run the entire suite.
  ///
  /// Test cases may use this to, for example, enable compression at the connection level on a
  /// per-test basis.
  ///
  /// - Parameter defaults: The default configuration for the test run.
  func configure(builder: ClientConnection.Builder)
}

extension InteroperabilityTest {
  func configure(builder: ClientConnection.Builder) {
  }
}

/// Test cases as listed by the [gRPC interoperability test description
/// specification](https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md).
///
/// This is not a complete list, the following tests have not been implemented:
/// - compute_engine_creds
/// - jwt_token_creds
/// - oauth2_auth_token
/// - per_rpc_creds
/// - google_default_credentials
/// - compute_engine_channel_credentials
///
/// Note: a description from the specification is included inline for each test as documentation for
/// its associated `InteroperabilityTest` class.
public enum InteroperabilityTestCase: String, CaseIterable {
  case emptyUnary = "empty_unary"
  case cacheableUnary = "cacheable_unary"
  case largeUnary = "large_unary"
  case clientCompressedUnary = "client_compressed_unary"
  case serverCompressedUnary = "server_compressed_unary"
  case clientStreaming = "client_streaming"
  case clientCompressedStreaming = "client_compressed_streaming"
  case serverStreaming = "server_streaming"
  case serverCompressedStreaming = "server_compressed_streaming"
  case pingPong = "ping_pong"
  case emptyStream = "empty_stream"
  case customMetadata = "custom_metadata"
  case statusCodeAndMessage = "status_code_and_message"
  case specialStatusMessage = "special_status_message"
  case unimplementedMethod = "unimplemented_method"
  case unimplementedService = "unimplemented_service"
  case cancelAfterBegin = "cancel_after_begin"
  case cancelAfterFirstResponse = "cancel_after_first_response"
  case timeoutOnSleepingServer = "timeout_on_sleeping_server"

  public var name: String {
    return self.rawValue
  }
}

extension InteroperabilityTestCase {
  /// Return a new instance of the test case.
  public func makeTest() -> InteroperabilityTest {
    switch self {
    case .emptyUnary:
      return EmptyUnary()
    case .cacheableUnary:
      return CacheableUnary()
    case .largeUnary:
      return LargeUnary()
    case .clientCompressedUnary:
      return ClientCompressedUnary()
    case .serverCompressedUnary:
      return ServerCompressedUnary()
    case .clientStreaming:
      return ClientStreaming()
    case .clientCompressedStreaming:
      return ClientCompressedStreaming()
    case .serverStreaming:
      return ServerStreaming()
    case .serverCompressedStreaming:
      return ServerCompressedStreaming()
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
    case .cancelAfterBegin:
      return CancelAfterBegin()
    case .cancelAfterFirstResponse:
      return CancelAfterFirstResponse()
    case .timeoutOnSleepingServer:
      return TimeoutOnSleepingServer()
    }
  }

  /// The set of server features required to run this test.
  public var requiredServerFeatures: Set<ServerFeature> {
    switch self {
    case .emptyUnary:
      return [.emptyCall]
    case .cacheableUnary:
      return [.cacheableUnaryCall]
    case .largeUnary:
      return [.unaryCall]
    case .clientStreaming:
      return [.streamingInputCall]
    case .clientCompressedStreaming:
      return [.streamingInputCall, .compressedRequest]
    case .clientCompressedUnary:
      return [.unaryCall, .compressedRequest]
    case .serverCompressedUnary:
      return [.unaryCall, .compressedResponse]
    case .serverStreaming:
      return [.streamingOutputCall]
    case .serverCompressedStreaming:
      return [.streamingOutputCall, .compressedResponse]
    case .pingPong:
      return [.fullDuplexCall]
    case .emptyStream:
      return [.fullDuplexCall]
    case .customMetadata:
      return [.unaryCall, .fullDuplexCall, .echoMetadata]
    case .statusCodeAndMessage:
      return [.unaryCall, .fullDuplexCall, .echoStatus]
    case .specialStatusMessage:
      return [.unaryCall, .echoStatus]
    case .unimplementedMethod:
      return []
    case .unimplementedService:
      return []
    case .cancelAfterBegin:
      return [.streamingInputCall]
    case .cancelAfterFirstResponse:
      return [.fullDuplexCall]
    case .timeoutOnSleepingServer:
      return [.fullDuplexCall]
    }
  }
}
