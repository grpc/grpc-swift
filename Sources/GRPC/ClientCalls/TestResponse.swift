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
import NIOHPACK
import NIO

enum Event<Message: GRPCPayload> {
  case message(Message)
  case statusAndTrailingMetadata(GRPCStatus, HPACKHeaders)
}

enum EventDelivery<Message: GRPCPayload> {
  case buffered([Event<Message>])
  case callback((Message) -> Void)
  case notRequired
}

public class StreamingTestResponse<Response: GRPCPayload> {
  internal let initialMetadata: EventLoopFuture<HPACKHeaders>
  internal let trailingMetadata: EventLoopPromise<HPACKHeaders>
  internal let status: EventLoopPromise<GRPCStatus>
  internal let eventLoop: EventLoop
  private var eventDelivery: EventDelivery<Response> = .buffered([])

  public init(eventLoop: EventLoop, initialMetadata: HPACKHeaders = [:]) {
    self.initialMetadata = eventLoop.makeSucceededFuture(initialMetadata)
    self.trailingMetadata = eventLoop.makePromise()
    self.status = eventLoop.makePromise()
    self.eventLoop = eventLoop
  }

  public func sendResponse(_ message: Response) {
    switch self.eventDelivery {
    case .buffered(var events):
      events.append(.message(message))
      self.eventDelivery = .buffered(events)

    case .callback(let callback):
      callback(message)

    case .notRequired:
      ()
    }
  }

  public func sendEnd(status: GRPCStatus = .ok, metadata: HPACKHeaders = [:]) {
    self.trailingMetadata.succeed(metadata)
    self.status.succeed(status)

    switch self.eventDelivery {
    case .buffered(var events):
      events.append(.statusAndTrailingMetadata(status, metadata))
      self.eventDelivery = .buffered(events)

    case .callback:
      self.trailingMetadata.succeed(metadata)
      self.status.succeed(status)
      self.eventDelivery = .notRequired

    case .notRequired:
      ()
    }

  }

  public static func makeFailed() -> StreamingTestResponse<Response> {
    let loop = EmbeddedEventLoop()
    let call = StreamingTestResponse(eventLoop: loop)
    let status = GRPCStatus(
      code: .failedPrecondition,
      message: "Test response must be added before calling the RPC"
    )
    call.sendEnd(status: status)
    try! loop.syncShutdownGracefully()
    return call
  }
}

extension StreamingTestResponse {
  internal func provideCallback(_ callback: @escaping (Response) -> Void) {
    switch self.eventDelivery {
    case .buffered(let events):
      var retainCallback = true

      for event in events {
        switch event {
        case .message(let message):
          callback(message)

        case .statusAndTrailingMetadata(let status, let trailers):
          self.sendEnd(status: status, metadata: trailers)
          // Drop any messages after this; it's a user-error, we also no longer require the
          // callback to be held.
          retainCallback = false
          break
        }
      }

      if retainCallback {
        self.eventDelivery = .callback(callback)
      } else {
        self.eventDelivery = .notRequired
      }

    case .callback, .notRequired:
      preconditionFailure("Invalid state event delivery state")
    }
  }
}

public class UnaryTestResponse<Response: GRPCPayload> {
  internal let eventLoop: EventLoop
  internal let initialMetadata: EventLoopFuture<HPACKHeaders>
  internal let response: EventLoopPromise<Response>
  internal let trailingMetadata: EventLoopPromise<HPACKHeaders>
  internal let status: EventLoopPromise<GRPCStatus>

  public init(eventLoop: EventLoop, initialMetadata: HPACKHeaders = [:]) {
    self.eventLoop = eventLoop
    self.initialMetadata = eventLoop.makeSucceededFuture(initialMetadata)
    self.response = eventLoop.makePromise()
    self.trailingMetadata = eventLoop.makePromise()
    self.status = eventLoop.makePromise()
  }

  public func sendResponse(_ message: Response) {
    self.response.succeed(message)
  }

  public func sendEnd(status: GRPCStatus = .ok, metadata: HPACKHeaders = [:]) {
    self.response.fail(status)
    self.trailingMetadata.succeed(metadata)
    self.status.succeed(status)
  }

  public static func makeFailed() -> UnaryTestResponse<Response> {
    let loop = EmbeddedEventLoop()
    let call = UnaryTestResponse(eventLoop: loop)
    let status = GRPCStatus(
      code: .failedPrecondition,
      message: "Test response must be added before calling the RPC"
    )
    call.sendEnd(status: status)
    try! loop.syncShutdownGracefully()
    return call
  }
}
