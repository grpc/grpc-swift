/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation

/// Representation of a response to a gRPC call
public class CallResponse {

  /// Error code that could be generated when the call is created
  public var error: grpc_call_error

  /// Result of waiting for call completion
  public var completion: grpc_completion_type

  /// Status code returned by server
  public var status: Int

  /// Status message optionally returned by server
  public var statusDetails: String

  /// Message returned by server
  public var messageData: Data?

  /// Initial metadata returned by server
  public var initialMetadata: Metadata?

  /// Trailing metadata returned by server
  public var trailingMetadata: Metadata?

  /// Initializes a response when error != GRPC_CALL_OK
  ///
  /// - Parameter error: an error code from when the call was performed
  public init(error: grpc_call_error) {
    self.error = error
    self.completion = GRPC_OP_COMPLETE
    self.status = 0
    self.statusDetails = ""
  }

  /// Initializes a response when completion != GRPC_OP_COMPLETE
  ///
  /// - Parameter completion: a code indicating the result of waiting for the call to complete
  public init(completion: grpc_completion_type) {
    self.error = GRPC_CALL_OK
    self.completion = completion
    self.status = 0
    self.statusDetails = ""
  }

  /// Initializes a response when error == GRPC_CALL_OK and completion == GRPC_OP_COMPLETE
  ///
  /// - Parameter status: a status code returned from the server
  /// - Parameter statusDetails: a status string returned from the server
  /// - Parameter message: a buffer containing results returned from the server
  /// - Parameter initialMetadata: initial metadata returned by the server
  /// - Parameter trailingMetadata: trailing metadata returned by the server
  init(status:Int,
       statusDetails:String,
       message:ByteBuffer?,
       initialMetadata:Metadata?,
       trailingMetadata:Metadata?) {
    self.error = GRPC_CALL_OK
    self.completion = GRPC_OP_COMPLETE
    self.status = status
    self.statusDetails = statusDetails
    if let message = message {
      self.messageData = message.data()
    }
    self.initialMetadata = initialMetadata
    self.trailingMetadata = trailingMetadata
  }
}
