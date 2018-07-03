/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation

public struct ServerStatus: Error {
  public let code: StatusCode
  public let message: String
  public let trailingMetadata: Metadata

  public init(code: StatusCode, message: String, trailingMetadata: Metadata = Metadata()) {
    self.code = code
    self.message = message
    self.trailingMetadata = trailingMetadata
  }

  public static let ok = ServerStatus(code: .ok, message: "OK")
  public static let processingError = ServerStatus(code: .internalError, message: "unknown error processing request")
  public static let noRequestData = ServerStatus(code: .invalidArgument, message: "no request data received")
  public static let sendingInitialMetadataFailed = ServerStatus(code: .internalError, message: "sending initial metadata failed")
}
