/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import NIO
import NIOHPACK

/// This protocol lays out the inbound interface between the gRPC module and generated server code.
/// On receiving a new RPC, gRPC will ask all available service providers for an instance of this
/// protocol in order to handle the RPC.
///
/// See also: `CallHandlerProvider.handle(method:context:)`
public protocol GRPCServerHandlerProtocol {
  /// Called when request headers have been received at the start of an RPC.
  /// - Parameter metadata: The request headers.
  func receiveMetadata(_ metadata: HPACKHeaders)

  /// Called when request message has been received.
  /// - Parameter bytes: The bytes of the serialized request.
  func receiveMessage(_ bytes: ByteBuffer)

  /// Called at the end of the request stream.
  func receiveEnd()

  /// Called when an error has been encountered. The handler should be torn down on receiving an
  /// error.
  /// - Parameter error: The error which has been encountered.
  func receiveError(_ error: Error)

  /// Called when the RPC handler should be torn down.
  func finish()
}

/// This protocol defines the outbound interface between the gRPC module and generated server code.
/// It is used by server handlers in order to send responses back to gRPC.
@usableFromInline
internal protocol GRPCServerResponseWriter {
  /// Send the initial response metadata.
  /// - Parameters:
  ///   - metadata: The user-provided metadata to send to the client.
  ///   - promise: A promise to complete once the metadata has been handled.
  func sendMetadata(_ metadata: HPACKHeaders, promise: EventLoopPromise<Void>?)

  /// Send the serialized bytes of a response message.
  /// - Parameters:
  ///   - bytes: The serialized bytes to send to the client.
  ///   - metadata: Metadata associated with sending the response, such as whether it should be
  ///     compressed.
  ///   - promise: A promise to complete once the message as been handled.
  func sendMessage(_ bytes: ByteBuffer, metadata: MessageMetadata, promise: EventLoopPromise<Void>?)

  /// Ends the response stream.
  /// - Parameters:
  ///   - status: The final status of the RPC.
  ///   - trailers: Any user-provided trailers to send back to the client with the status.
  ///   - promise: A promise to complete once the status and trailers have been handled.
  func sendEnd(status: GRPCStatus, trailers: HPACKHeaders, promise: EventLoopPromise<Void>?)
}
