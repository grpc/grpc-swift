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

import NIOCore
import NIOHTTP2
import XCTest

func XCTAssertGoAway(
  _ payload: HTTP2Frame.FramePayload,
  verify: (HTTP2StreamID, HTTP2ErrorCode, ByteBuffer?) throws -> Void = { _, _, _ in }
) rethrows {
  switch payload {
  case .goAway(let lastStreamID, let errorCode, let opaqueData):
    try verify(lastStreamID, errorCode, opaqueData)
  default:
    XCTFail("Expected '.goAway' got '\(payload)'")
  }
}

func XCTAssertPing(
  _ payload: HTTP2Frame.FramePayload,
  verify: (HTTP2PingData, Bool) throws -> Void = { _, _ in }
) rethrows {
  switch payload {
  case .ping(let data, ack: let ack):
    try verify(data, ack)
  default:
    XCTFail("Expected '.ping' got '\(payload)'")
  }
}
