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

import GRPCInteroperabilityTestModels
import NIOHPACK
import SwiftProtobuf

import struct Foundation.Data

// MARK: - Payload creation

extension Grpc_Testing_Payload {
  static func bytes(of value: UInt64) -> Grpc_Testing_Payload {
    return Grpc_Testing_Payload.with { payload in
      withUnsafeBytes(of: value) { bytes in
        payload.body = Data(bytes)
      }
    }
  }

  static func zeros(count: Int) -> Grpc_Testing_Payload {
    return Grpc_Testing_Payload.with { payload in
      payload.body = Data(repeating: 0, count: count)
    }
  }
}

// MARK: - Bool value

extension Grpc_Testing_BoolValue: ExpressibleByBooleanLiteral {
  public typealias BooleanLiteralType = Bool

  public init(booleanLiteral value: Bool) {
    self = .with {
      $0.value = value
    }
  }
}

// MARK: - Echo status creation

extension Grpc_Testing_EchoStatus {
  init(code: Int32, message: String) {
    self = .with {
      $0.code = code
      $0.message = message
    }
  }
}

// MARK: - Response Parameter creation

extension Grpc_Testing_ResponseParameters {
  static func size(_ size: Int) -> Grpc_Testing_ResponseParameters {
    return Grpc_Testing_ResponseParameters.with { parameters in
      parameters.size = numericCast(size)
    }
  }
}

// MARK: - Echo status

protocol EchoStatusRequest: Message {
  var responseStatus: Grpc_Testing_EchoStatus { get set }
}

extension EchoStatusRequest {
  var shouldEchoStatus: Bool {
    return self.responseStatus != Grpc_Testing_EchoStatus()
  }
}

extension EchoStatusRequest {
  static func withStatus(of status: Grpc_Testing_EchoStatus) -> Self {
    return Self.with { instance in
      instance.responseStatus = status
    }
  }
}

extension Grpc_Testing_SimpleRequest: EchoStatusRequest {}
extension Grpc_Testing_StreamingOutputCallRequest: EchoStatusRequest {}

// MARK: - Payload request

protocol PayloadRequest: Message {
  var payload: Grpc_Testing_Payload { get set }
}

extension PayloadRequest {
  static func withPayload(of payload: Grpc_Testing_Payload) -> Self {
    return Self.with { instance in
      instance.payload = payload
    }
  }
}

extension Grpc_Testing_SimpleRequest: PayloadRequest {}
extension Grpc_Testing_StreamingOutputCallRequest: PayloadRequest {}
extension Grpc_Testing_StreamingInputCallRequest: PayloadRequest {}

// MARK: - Echo metadata

extension HPACKHeaders {
  /// See `ServerFeatures.echoMetadata`.
  var shouldEchoMetadata: Bool {
    return self.contains(name: "x-grpc-test-echo-initial")
      || self
        .contains(name: "x-grpc-test-echo-trailing-bin")
  }
}
