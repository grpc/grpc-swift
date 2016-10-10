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
import Foundation // for String.Encoding

/// Abstract representation of gRPC Operations
class Operation {

  /// Pointer to underlying C representation
  var observer: UnsafeMutableRawPointer

  /// Initializes an Operation Observer
  ///
  /// - Parameter observer: the underlying C representation
  init(observer: UnsafeMutableRawPointer) {
    self.observer = observer
  }

  deinit {
    cgrpc_observer_destroy(observer);
  }
}

/// SendInitialMetadata operation
class Operation_SendInitialMetadata : Operation {

  /// Initializes an Operation Observer
  ///
  /// - Parameter metadata: the initial metadata to send
  init(metadata:Metadata) {
    super.init(observer:cgrpc_observer_create_send_initial_metadata(metadata.array))
  }
}

/// SendMessage operation
class Operation_SendMessage : Operation {

  /// Initializes an Operation Observer
  ///
  /// - Parameter message: the message to send
  init(message:ByteBuffer) {
    super.init(observer:cgrpc_observer_create_send_message())
    cgrpc_observer_send_message_set_message(observer, message.underlyingByteBuffer);
  }
}

/// SendCloseFromClient operation
class Operation_SendCloseFromClient : Operation {

  /// Initializes an Operation Observer
  init() {
    super.init(observer:cgrpc_observer_create_send_close_from_client())
  }
}

/// SendStatusFrom Server operation
class Operation_SendStatusFromServer : Operation {

  /// Initializes an Operation Observer
  ///
  /// - Parameter status: the status code to send with the response
  /// - Parameter statusDetails: the status message to send with the response
  /// - Parameter metadata: the trailing metadata to send with the response
  init(status:Int,
       statusDetails:String,
       metadata:Metadata) {
    super.init(observer:cgrpc_observer_create_send_status_from_server(metadata.array))
    cgrpc_observer_send_status_from_server_set_status(observer, Int32(status));
    cgrpc_observer_send_status_from_server_set_status_details(observer, statusDetails);
  }
}

/// ReceiveInitialMetadata operation
class Operation_ReceiveInitialMetadata : Operation {

  /// Initializes an Operation Observer
  init() {
    super.init(observer:cgrpc_observer_create_recv_initial_metadata())
  }

  /// Gets the initial metadata that was received
  ///
  /// - Returns: metadata
  func metadata() -> Metadata {
    return Metadata(array:cgrpc_observer_recv_initial_metadata_get_metadata(observer));
  }
}

/// ReceiveMessage operation
class Operation_ReceiveMessage : Operation {

  /// Initializes an Operation Observer
  init() {
    super.init(observer:cgrpc_observer_create_recv_message())
  }

  /// Gets the message that was received
  ///
  /// - Returns: message
  func message() -> ByteBuffer? {
    if let b = cgrpc_observer_recv_message_get_message(observer) {
      return ByteBuffer(underlyingByteBuffer:b)
    } else {
      return nil
    }
  }
}

/// ReceiveStatusOnClient operation
class Operation_ReceiveStatusOnClient : Operation {

  /// Initializes an Operation Observer
  init() {
    super.init(observer:cgrpc_observer_create_recv_status_on_client())
  }

  /// Gets the trailing metadata that was received
  ///
  /// - Returns: metadata
  func metadata() -> Metadata {
    return Metadata(array:cgrpc_observer_recv_status_on_client_get_metadata(observer));
  }

  /// Gets the status code that was received
  ///
  /// - Returns: status code
  func status() -> Int {
    return cgrpc_observer_recv_status_on_client_get_status(observer);
  }

  /// Gets the status message that was received
  ///
  /// - Returns: status message
  func statusDetails() -> String {
    return String(cString:cgrpc_observer_recv_status_on_client_get_status_details(observer),
                  encoding:String.Encoding.utf8)!
  }
}

/// ReceiveCloseOnServer operation
class Operation_ReceiveCloseOnServer : Operation {

  /// Initializes an Operation Observer
  init() {
    super.init(observer:cgrpc_observer_create_recv_close_on_server())
  }
}
