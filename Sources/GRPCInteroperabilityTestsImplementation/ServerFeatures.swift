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

/// Server features which may be required for tests.
///
/// We use this enum to match up tests we can run on the NIO client against the NIO server at
/// run time.
///
/// These features are listed in the [gRPC interoperability test description
/// specification](https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md).
///
/// Missing features:
/// - compressed response
/// - compressed request
/// - observe `ResponseParameter.interval_us`
/// - echo authenticated username
/// - echo authenticated OAuth scope
///
/// - Note: This is not a complete set of features, only those used in either the client or server.
public enum ServerFeature {
  /// See TestServiceProvider_NIO.emptyCall.
  case emptyCall

  /// See TestServiceProvider_NIO.unaryCall.
  case unaryCall

  /// See TestServiceProvider_NIO.cacheableUnaryCall.
  case cacheableUnaryCall

  /// When the client sets expect_compressed to true, the server expects the client request to be
  /// compressed. If it's not, it fails the RPC with INVALID_ARGUMENT. Note that
  /// `response_compressed` is present on both SimpleRequest (unary) and StreamingOutputCallRequest
  /// (streaming).
  case compressedRequest

  /// When the client sets response_compressed to true, the server's response is sent back
  /// compressed. Note that response_compressed is present on both SimpleRequest (unary) and
  /// StreamingOutputCallRequest (streaming).
  case compressedResponse

  /// See TestServiceProvider_NIO.streamingInputCall.
  case streamingInputCall

  /// See TestServiceProvider_NIO.streamingOutputCall.
  case streamingOutputCall

  /// See TestServiceProvider_NIO.fullDuplexCall.
  case fullDuplexCall

  /// When the client sends a `responseStatus` in the request payload, the server closes the stream
  /// with the status code and messsage contained within said `responseStatus`. The server will not
  /// process any further messages on the stream sent by the client. This can be used by clients to
  /// verify correct handling of different status codes and associated status messages end-to-end.
  case echoStatus

  /// When the client sends metadata with the key "x-grpc-test-echo-initial" with its request,
  /// the server sends back exactly this key and the corresponding value back to the client as
  /// part of initial metadata. When the client sends metadata with the key
  /// "x-grpc-test-echo-trailing-bin" with its request, the server sends back exactly this key
  /// and the corresponding value back to the client as trailing metadata.
  case echoMetadata
}
