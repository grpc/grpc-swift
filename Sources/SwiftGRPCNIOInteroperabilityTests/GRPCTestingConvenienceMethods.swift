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
import SwiftProtobuf
import NIOHTTP1

// MARK: - Payload creation
extension Grpc_Testing_Payload {
  static func bytes<T>(of body: inout T) -> Grpc_Testing_Payload {
    return Grpc_Testing_Payload.with { payload in
      payload.body = Data(bytes: &body, count: MemoryLayout.size(ofValue: body))
    }
  }

  static func zeros(count: Int) -> Grpc_Testing_Payload {
    return Grpc_Testing_Payload.with { payload in
      payload.body = Data(repeating: 0, count: count)
    }
  }
}

// MARK: - Echo status creation
extension Grpc_Testing_EchoStatus {
  init(code: Int32, message: String) {
    self.code = code
    self.message = message
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

extension Grpc_Testing_SimpleRequest: EchoStatusRequest { }
extension Grpc_Testing_StreamingOutputCallRequest: EchoStatusRequest { }

// MARK: - Echo metadata

extension HTTPHeaders {
  /// See `ServerFeatures.echoMetadata`.
  var shouldEchoMetadata: Bool {
    return self.contains(name: "x-grpc-test-echo-initial") || self.contains(name: "x-grpc-test-echo-trailing-bin")
  }
}
