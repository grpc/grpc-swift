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

/// A bucket of promises for a unary-response RPC.
internal class UnaryResponseParts<Response> {
  /// The `EventLoop` we expect to receive these response parts on.
  private let eventLoop: EventLoop

  /// A promise for the `Response` message.
  private let responsePromise: EventLoopPromise<Response>

  /// Lazy promises for the status, initial-, and trailing-metadata.
  private var initialMetadataPromise: LazyEventLoopPromise<HPACKHeaders>
  private var trailingMetadataPromise: LazyEventLoopPromise<HPACKHeaders>
  private var statusPromise: LazyEventLoopPromise<GRPCStatus>

  internal var response: EventLoopFuture<Response> {
    return self.responsePromise.futureResult
  }

  internal var initialMetadata: EventLoopFuture<HPACKHeaders> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.initialMetadataPromise.getFutureResult()
    }
  }

  internal var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.trailingMetadataPromise.getFutureResult()
    }
  }

  internal var status: EventLoopFuture<GRPCStatus> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.statusPromise.getFutureResult()
    }
  }

  internal init(on eventLoop: EventLoop) {
    self.eventLoop = eventLoop
    self.responsePromise = eventLoop.makePromise()
    self.initialMetadataPromise = eventLoop.makeLazyPromise()
    self.trailingMetadataPromise = eventLoop.makeLazyPromise()
    self.statusPromise = eventLoop.makeLazyPromise()
  }

  /// Handle the response part, completing any promises as necessary.
  /// - Important: This *must* be called on `eventLoop`.
  internal func handle(_ part: ClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()

    switch part {
    case let .metadata(metadata):
      self.initialMetadataPromise.succeed(metadata)

    case let .message(response):
      self.responsePromise.succeed(response)

    case let .end(status, trailers):
      // In case of a "Trailers-Only" RPC (i.e. just the trailers and status), fail the initial
      // metadata and trailers.
      self.initialMetadataPromise.fail(status)
      self.responsePromise.fail(status)

      self.trailingMetadataPromise.succeed(trailers)
      self.statusPromise.succeed(status)

    case let .error(error):
      let withoutContext = error.removingContext()
      let status = withoutContext.makeGRPCStatus()
      self.initialMetadataPromise.fail(withoutContext)
      self.responsePromise.fail(withoutContext)
      self.trailingMetadataPromise.fail(withoutContext)
      self.statusPromise.succeed(status)
    }
  }
}

/// A bucket of promises for a streaming-response RPC.
internal class StreamingResponseParts<Response> {
  /// The `EventLoop` we expect to receive these response parts on.
  private let eventLoop: EventLoop

  /// A callback for response messages.
  private let responseCallback: (Response) -> Void

  /// Lazy promises for the status, initial-, and trailing-metadata.
  private var initialMetadataPromise: LazyEventLoopPromise<HPACKHeaders>
  private var trailingMetadataPromise: LazyEventLoopPromise<HPACKHeaders>
  private var statusPromise: LazyEventLoopPromise<GRPCStatus>

  internal var initialMetadata: EventLoopFuture<HPACKHeaders> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.initialMetadataPromise.getFutureResult()
    }
  }

  internal var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.trailingMetadataPromise.getFutureResult()
    }
  }

  internal var status: EventLoopFuture<GRPCStatus> {
    return self.eventLoop.executeOrFlatSubmit {
      return self.statusPromise.getFutureResult()
    }
  }

  internal init(on eventLoop: EventLoop, _ responseCallback: @escaping (Response) -> Void) {
    self.eventLoop = eventLoop
    self.responseCallback = responseCallback
    self.initialMetadataPromise = eventLoop.makeLazyPromise()
    self.trailingMetadataPromise = eventLoop.makeLazyPromise()
    self.statusPromise = eventLoop.makeLazyPromise()
  }

  internal func handle(_ part: ClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()

    switch part {
    case let .metadata(metadata):
      self.initialMetadataPromise.succeed(metadata)

    case let .message(response):
      self.responseCallback(response)

    case let .end(status, trailers):
      self.initialMetadataPromise.fail(status)
      self.trailingMetadataPromise.succeed(trailers)
      self.statusPromise.succeed(status)

    case let .error(error):
      let withoutContext = error.removingContext()
      let status = withoutContext.makeGRPCStatus()
      self.initialMetadataPromise.fail(withoutContext)
      self.trailingMetadataPromise.fail(withoutContext)
      self.statusPromise.succeed(status)
    }
  }
}

extension EventLoop {
  fileprivate func executeOrFlatSubmit<Result>(
    _ body: @escaping () -> EventLoopFuture<Result>
  ) -> EventLoopFuture<Result> {
    if self.inEventLoop {
      return body()
    } else {
      return self.flatSubmit {
        return body()
      }
    }
  }
}

extension Error {
  fileprivate func removingContext() -> Error {
    if let withContext = self as? GRPCError.WithContext {
      return withContext.error
    } else {
      return self
    }
  }

  fileprivate func makeGRPCStatus() -> GRPCStatus {
    if let withContext = self as? GRPCError.WithContext {
      return withContext.error.makeGRPCStatus()
    } else if let transformable = self as? GRPCStatusTransformable {
      return transformable.makeGRPCStatus()
    } else {
      return GRPCStatus(code: .unknown, message: String(describing: self))
    }
  }
}
