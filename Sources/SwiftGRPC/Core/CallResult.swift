/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
import Dispatch
#endif
import Foundation

public struct CallResult: CustomStringConvertible {
  public let success: Bool
  public let statusCode: StatusCode
  public let statusMessage: String?
  public let resultData: Data?
  public let initialMetadata: Metadata?
  public let trailingMetadata: Metadata?
  
  init(_ op: OperationGroup) {
    success = op.success
    if let statusCodeRawValue = op.receivedStatusCode(),
      let statusCode = StatusCode(rawValue: statusCodeRawValue) {
      self.statusCode = statusCode
    } else {
      statusCode = .unknown
    }
    statusMessage = op.receivedStatusMessage()
    resultData = op.receivedMessage()?.data()
    initialMetadata = op.receivedInitialMetadata()
    trailingMetadata = op.receivedTrailingMetadata()
  }
  
  fileprivate init(success: Bool, statusCode: StatusCode, statusMessage: String?, resultData: Data?,
                   initialMetadata: Metadata?, trailingMetadata: Metadata?) {
    self.success = success
    self.statusCode = statusCode
    self.statusMessage = statusMessage
    self.resultData = resultData
    self.initialMetadata = initialMetadata
    self.trailingMetadata = trailingMetadata
  }
  
  public var description: String {
    var result = "\(success ? "successful" : "unsuccessful"), status \(statusCode)"
    if let statusMessage = self.statusMessage {
      result += ": " + statusMessage
    }
    if let resultData = self.resultData {
      result += "\nresultData: "
      result += resultData.description
    }
    if let initialMetadata = self.initialMetadata {
      result += "\ninitialMetadata: "
      result += initialMetadata.description
    }
    if let trailingMetadata = self.trailingMetadata {
      result += "\ntrailingMetadata: "
      result += trailingMetadata.description
    }
    return result
  }
  
  static let fakeOK = CallResult(success: true, statusCode: .ok, statusMessage: "OK", resultData: nil,
                                 initialMetadata: nil, trailingMetadata: nil)
}
