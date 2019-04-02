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
import SwiftGRPCNIO
import NIO
import NIOHTTP1

/// Server features which may be required for tests.
///
/// We use this enum to match up tests we can run on the NIO client against the NIO server at
/// run time.
///
/// These features are listed in the [gRPC interopability test description
/// specification](https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md).
///
/// - Note: This is not a complete set of features, only those used in either the client or server.
public enum ServerFeature {
  case emptyCall
  case unaryCall
  case cacheableUnaryCall
  case streamingInputCall
  case streamingOutputCall
  case fullDuplexCall
  case echoStatus
  case echoMetadata
}

public protocol InteropabilityTest {
  /// Run a test case using the given connection.
  ///
  /// The test case is considered unsuccessful if any exception is thrown, conversely if no
  /// exceptions are thrown it is successful.
  ///
  /// - Parameter connection: The connection to use for the test.
  /// - Throws: Any exception may be thrown to indicate an unsuccessful test.
  func run(using connection: GRPCClientConnection) throws
}

/// Test cases as listed by the [gRPC interopability test description
/// specification](https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md).
///
/// Note: a description from the specification is included inline for each test as documentation for
/// its associated `InteropabilityTest` class.
public enum InteropabilityTestCase: String, CaseIterable {
  case emptyUnary = "empty_unary"
  case cacheableUnary = "cacheable_unary"
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
  case cancelAfterBegin = "cancel_after_begin"
  case cancelAfterFirstResponse = "cancel_after_first_response"
  case timeoutOnSleepingServer = "timeout_on_sleeping_server"

  public var name: String {
    return self.rawValue
  }
}

extension InteropabilityTestCase {
  /// Return a new instance of the test case.
  public func makeTest() -> InteropabilityTest {
    switch self {
    case .emptyUnary:
      return EmptyUnary()
    case .cacheableUnary:
      return CacheableUnary()
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
    case .serverStreaming:
      return [.streamingOutputCall]
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
