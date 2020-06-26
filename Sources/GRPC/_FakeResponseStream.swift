/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

public enum FakeRequestPart<Request: GRPCPayload> {
  case metadata(HPACKHeaders)
  case message(Request)
  case end
}

/// Sending on a fake response stream would have resulted in a protocol violation (such as
/// sending initial metadata multiple times or sending messages after the stream has closed).
public struct FakeResponseProtocolViolation: Error, Hashable {
  /// The reason that sending the message would have resulted in a protocol violation.
  public var reason: String

  init(_ reason: String) {
    self.reason = reason
  }
}

/// A fake response stream into which users may inject response parts for use in unit tests.
///
/// Users may not interact with this class directly but may do so via one of its subclasses
/// `FakeUnaryResponse` and `FakeStreamingResponse`.
public class _FakeResponseStream<Request: GRPCPayload, Response: GRPCPayload> {
  private enum StreamEvent {
    case responsePart(_GRPCClientResponsePart<Response>)
    case error(Error)
  }

  /// The channel to use for communication.
  internal let channel: EmbeddedChannel

  /// A buffer to hold responses in before the proxy is activated.
  private var responseBuffer: CircularBuffer<StreamEvent>

  /// The current state of the proxy.
  private var activeState: ActiveState

  /// The state of sending response parts.
  private var sendState: SendState

  private enum ActiveState {
    case inactive
    case active
  }

  private enum SendState {
    // Nothing has been sent; we can send initial metadata to become 'sending' or trailing metadata
    // to start 'closing'.
    case idle

    // We're sending messages. We can send more messages in this state or trailing metadata to
    // transition to 'closing'.
    case sending

    // We're closing: we've sent trailing metadata, we may only send a status now to close.
    case closing

    // Closed, nothing more can be sent.
    case closed
  }

  internal init(requestHandler: @escaping (FakeRequestPart<Request>) -> ()) {
    self.activeState = .inactive
    self.sendState = .idle
    self.responseBuffer = CircularBuffer()
    self.channel = EmbeddedChannel(handler: WriteCapturingHandler(requestHandler: requestHandler))
  }

  /// Activate the test proxy; this should be called
  internal func activate() {
    switch self.activeState {
    case .inactive:
      // Activate the channel. This will allow any request parts to be sent.
      self.channel.pipeline.fireChannelActive()

      // Unbuffer any response parts.
      while !self.responseBuffer.isEmpty {
        self.write(self.responseBuffer.removeFirst())
      }

      // Now we're active.
      self.activeState = .active

    case .active:
      ()
    }
  }

  /// Write or buffer the response part, depending on the our current state.
  internal func _sendResponsePart(_ part: _GRPCClientResponsePart<Response>) throws {
    try self.send(.responsePart(part))
  }

  internal func _sendError(_ error: Error) throws {
    try self.send(.error(error))
  }

  private func send(_ event: StreamEvent) throws {
    switch self.validate(event) {
    case .valid:
      self.writeOrBuffer(event)

    case .validIfSentAfter(let extraPart):
      self.writeOrBuffer(extraPart)
      self.writeOrBuffer(event)

    case .invalid(let reason):
      throw FakeResponseProtocolViolation(reason)
    }
  }

  /// Validate events the user wants to send on the stream.
  private func validate(_ event: StreamEvent) -> Validation {
    switch (event, self.sendState) {
    case (.responsePart(.initialMetadata), .idle):
      self.sendState = .sending
      return .valid

    case (.responsePart(.initialMetadata), .sending),
         (.responsePart(.initialMetadata), .closing),
         (.responsePart(.initialMetadata), .closed):
      // We can only send initial metadata from '.idle'.
      return .invalid(reason: "Initial metadata has already been sent")

    case (.responsePart(.message), .idle):
      // This is fine: we don't force the user to specify initial metadata so we send some on their
      // behalf.
      self.sendState = .sending
      return .validIfSentAfter(.responsePart(.initialMetadata([:])))

    case (.responsePart(.message), .sending):
      return .valid

    case (.responsePart(.message), .closing),
         (.responsePart(.message), .closed):
      // We can't send messages once we're closing or closed.
      return .invalid(reason: "Messages can't be sent after the stream has been closed")

    case (.responsePart(.trailingMetadata), .idle),
         (.responsePart(.trailingMetadata), .sending):
      self.sendState = .closing
      return .valid

    case (.responsePart(.trailingMetadata), .closing),
         (.responsePart(.trailingMetadata), .closed):
      // We're already closing or closed.
      return .invalid(reason: "Trailing metadata can't be sent after the stream has been closed")

    case (.responsePart(.status), .idle),
         (.error, .idle),
         (.responsePart(.status), .sending),
         (.error, .sending),
         (.responsePart(.status), .closed),
         (.error, .closed):
      // We can only error/close if we're closing (i.e. have already sent trailers which we enforce
      // from the API in the subclasses).
      return .invalid(reason: "Status/error can only be sent after trailing metadata has been sent")

    case (.responsePart(.status), .closing),
         (.error, .closing):
      self.sendState = .closed
      return .valid
    }
  }

  private enum Validation {
    /// Sending the part is valid.
    case valid

    /// Sending the part, if it is sent after the given part.
    case validIfSentAfter(_ part: StreamEvent)

    /// Sending the part would be a protocol violation.
    case invalid(reason: String)
  }

  private func writeOrBuffer(_ event: StreamEvent) {
    switch self.activeState {
    case .inactive:
      self.responseBuffer.append(event)

    case .active:
      self.write(event)
    }
  }

  private func write(_ part: StreamEvent) {
    switch part {
    case .error(let error):
      self.channel.pipeline.fireErrorCaught(error)

    case .responsePart(let responsePart):
      // We tolerate errors here: an error will be thrown if the write results in an error which
      // isn't caught in the channel. Errors in the channel get funnelled into the transport held
      // by the actual call object and handled there.
      _ = try? self.channel.writeInbound(responsePart)
    }
  }
}

// MARK: - Unary Response

/// A fake unary response to be used with a generated test client.
///
/// Users typically create fake responses via helper methods on their generated test clients
/// corresponding to the RPC which they intend to test.
///
/// For unary responses users may call one of two functions for each RPC:
/// - `sendMessage(_:initialMetadata:trailingMetadata:status)`, or
/// - `sendError(status:trailingMetadata)`
///
/// `sendMessage` sends a normal unary response with the provided message and allows the caller to
/// also specify initial metadata, trailing metadata and the status. Both metadata arguments are
/// empty by default and the status defaults to one with an 'ok' status code.
///
/// `sendError` may be used to terminate an RPC without providing a response. As for `sendMessage`,
/// the `trailingMetadata` defaults to being empty.
public class FakeUnaryResponse<Request: GRPCPayload, Response: GRPCPayload>: _FakeResponseStream<Request, Response> {
  public override init(requestHandler: @escaping (FakeRequestPart<Request>) -> () = { _ in }) {
    super.init(requestHandler: requestHandler)
  }

  /// Send a response message to the client.
  ///
  /// - Parameters:
  ///   - response: The message to send.
  ///   - initialMetadata: The initial metadata to send. By default the metadata will be empty.
  ///   - trailingMetadata: The trailing metadata to send. By default the metadata will be empty.
  ///   - status: The status to send. By default this has an '.ok' status code.
  /// - Throws: FakeResponseProtocolViolation if sending the message would violate the gRPC
  ///   protocol, e.g. sending messages after the RPC has ended.
  public func sendMessage(
    _ response: Response,
    initialMetadata: HPACKHeaders = [:],
    trailingMetadata: HPACKHeaders = [:],
    status: GRPCStatus = .ok
  ) throws {
    try self._sendResponsePart(.initialMetadata(initialMetadata))
    try self._sendResponsePart(.message(.init(response, compressed: false)))
    try self._sendResponsePart(.trailingMetadata(trailingMetadata))
    try self._sendResponsePart(.status(status))
  }

  /// Send an error to the client.
  ///
  /// - Parameters:
  ///   - error: The error to send.
  ///   - trailingMetadata: The trailing metadata to send. By default the metadata will be empty.
  public func sendError(_ error: Error, trailingMetadata: HPACKHeaders = [:]) throws {
    try self._sendResponsePart(.trailingMetadata(trailingMetadata))
    try self._sendError(error)
  }
}

// MARK: - Streaming Response

/// A fake streaming response to be used with a generated test client.
///
/// Users typically create fake responses via helper methods on their generated test clients
/// corresponding to the RPC which they intend to test.
///
/// For streaming responses users have a number of methods available to them:
/// - `sendInitialMetadata(_:)`
/// - `sendMessage(_:)`
/// - `sendEnd(status:trailingMetadata:)`
/// - `sendError(_:trailingMetadata)`
///
/// `sendInitialMetadata` may be called to send initial metadata to the client, however, it
/// must be called first in order for the metadata to be sent. If it is not called, empty
/// metadata will be sent automatically if necessary.
///
/// `sendMessage` may be called to send a response message on the stream. This may be called
/// multiple times. Messages will be ignored if this is called after `sendEnd` or `sendError`.
///
/// `sendEnd` indicates that the response stream has closed. It – or `sendError` - must be called
/// once. The `status` defaults to a value with the `ok` code and `trailingMetadata` is empty by
/// default.
///
/// `sendError` may be called at any time to indicate an error on the response stream.
/// Like `sendEnd`, `trailingMetadata` is empty by default.
public class FakeStreamingResponse<Request: GRPCPayload, Response: GRPCPayload>: _FakeResponseStream<Request, Response> {
  public override init(requestHandler: @escaping (FakeRequestPart<Request>) -> () = { _ in }) {
    super.init(requestHandler: requestHandler)
  }

  /// Send initial metadata to the client.
  ///
  /// Note that calling this function is not required; empty initial metadata will be sent
  /// automatically if necessary.
  ///
  /// - Parameter metadata: The metadata to send
  /// - Throws: FakeResponseProtocolViolation if sending initial metadata would violate the gRPC
  ///   protocol, e.g. sending metadata too many times, or out of order.
  public func sendInitialMetadata(_ metadata: HPACKHeaders) throws {
    try self._sendResponsePart(.initialMetadata(metadata))
  }

  /// Send a response message to the client.
  ///
  /// - Parameter response: The response to send.
  /// - Throws: FakeResponseProtocolViolation if sending the message would violate the gRPC
  ///   protocol, e.g. sending messages after the RPC has ended.
  public func sendMessage(_ response: Response) throws {
    try self._sendResponsePart(.message(.init(response, compressed: false)))
  }

  /// Send the RPC status and trailing metadata to the client.
  ///
  /// - Parameters:
  ///   - status: The status to send. By default the status code will be '.ok'.
  ///   - trailingMetadata: The trailing metadata to send. Empty by default.
  /// - Throws: FakeResponseProtocolViolation if ending the RPC would violate the gRPC
  ///   protocol, e.g. sending end after the RPC has already completed.
  public func sendEnd(status: GRPCStatus = .ok, trailingMetadata: HPACKHeaders = [:]) throws {
    try self._sendResponsePart(.trailingMetadata(trailingMetadata))
    try self._sendResponsePart(.status(status))
  }

  /// Send an error to the client.
  ///
  /// - Parameters:
  ///   - error: The error to send.
  ///   - trailingMetadata: The trailing metadata to send. By default the metadata will be empty.
  /// - Throws: FakeResponseProtocolViolation if sending the error would violate the gRPC
  ///   protocol, e.g. erroring after the RPC has already completed.
  public func sendError(_ error: Error, trailingMetadata: HPACKHeaders = [:]) throws {
    try self._sendResponsePart(.trailingMetadata(trailingMetadata))
    try self._sendError(error)
  }
}
