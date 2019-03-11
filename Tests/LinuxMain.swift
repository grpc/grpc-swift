/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import XCTest
@testable import SwiftGRPCTests
@testable import SwiftGRPCNIOTests

XCTMain([
  // SwiftGRPC
  testCase(gRPCTests.allTests),
  testCase(ChannelArgumentTests.allTests),
  testCase(ChannelConnectivityTests.allTests),
  testCase(ChannelShutdownTests.allTests),
  testCase(ClientCancellingTests.allTests),
  testCase(ClientTestExample.allTests),
  testCase(ClientTimeoutTests.allTests),
  testCase(CompletionQueueTests.allTests),
  testCase(ConnectionFailureTests.allTests),
  testCase(EchoTests.allTests),
  testCase(EchoTestsSecure.allTests),
  testCase(EchoTestsMutualAuth.allTests),
  testCase(MetadataTests.allTests),
  testCase(ServerCancellingTests.allTests),
  testCase(ServerTestExample.allTests),
  testCase(SwiftGRPCTests.ServerThrowingTests.allTests),
  testCase(ServerTimeoutTests.allTests),

  // SwiftGRPCNIO
  testCase(NIOServerTests.allTests),
  testCase(SwiftGRPCNIOTests.ServerThrowingTests.allTests),
  testCase(SwiftGRPCNIOTests.ServerDelayedThrowingTests.allTests),
  testCase(SwiftGRPCNIOTests.ClientThrowingWhenServerReturningErrorTests.allTests),
  testCase(NIOClientCancellingTests.allTests),
  testCase(NIOClientTimeoutTests.allTests),
  testCase(NIOServerWebTests.allTests),
  testCase(GRPCChannelHandlerTests.allTests),
  testCase(HTTP1ToRawGRPCServerCodecTests.allTests),
  testCase(LengthPrefixedMessageReaderTests.allTests),
])
