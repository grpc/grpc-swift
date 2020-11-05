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
@testable import GRPC
import NIO
import NIOHPACK
import XCTest

class ServerInterceptorPipelineTests: GRPCTestCase {
  override func setUp() {
    super.setUp()
    self.embeddedEventLoop = EmbeddedEventLoop()
  }

  private var embeddedEventLoop: EmbeddedEventLoop!

  private func makePipeline<Request, Response>(
    requests: Request.Type = Request.self,
    responses: Response.Type = Response.self,
    path: String = "/foo/bar",
    callType: GRPCCallType = .unary,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    onRequestPart: @escaping (GRPCServerRequestPart<Request>) -> Void,
    onResponsePart: @escaping (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void
  ) -> ServerInterceptorPipeline<Request, Response> {
    return ServerInterceptorPipeline(
      logger: self.logger,
      eventLoop: self.embeddedEventLoop,
      path: path,
      callType: callType,
      interceptors: interceptors,
      onRequestPart: onRequestPart,
      onResponsePart: onResponsePart
    )
  }

  func testEmptyPipeline() {
    var requestParts: [GRPCServerRequestPart<String>] = []
    var responseParts: [GRPCServerResponsePart<String>] = []

    let pipeline = self.makePipeline(
      requests: String.self,
      responses: String.self,
      onRequestPart: { requestParts.append($0) },
      onResponsePart: { part, promise in
        responseParts.append(part)
        assertThat(promise, .is(.nil()))
      }
    )

    pipeline.receive(.metadata([:]))
    pipeline.receive(.message("foo"))
    pipeline.receive(.end)

    assertThat(requestParts, .hasCount(3))
    assertThat(requestParts[0].metadata, .is([:]))
    assertThat(requestParts[1].message, .is("foo"))
    assertThat(requestParts[2].isEnd, .is(true))

    pipeline.send(.metadata([:]), promise: nil)
    pipeline.send(.message("bar", .init(compress: false, flush: false)), promise: nil)
    pipeline.send(.end(.ok, [:]), promise: nil)

    assertThat(responseParts, .hasCount(3))
    assertThat(responseParts[0].metadata, .is([:]))
    assertThat(responseParts[1].message, .is("bar"))
    assertThat(responseParts[2].end, .is(.notNil()))

    // Pipelines should now be closed. We can't send or receive.
    let p = self.embeddedEventLoop.makePromise(of: Void.self)
    pipeline.send(.metadata([:]), promise: p)
    assertThat(try p.futureResult.wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))

    responseParts.removeAll()
    pipeline.receive(.end)
    assertThat(responseParts, .isEmpty())
  }

  func testRecordingPipeline() {
    let recorder = RecordingServerInterceptor<String, String>()
    let pipeline = self.makePipeline(
      interceptors: [recorder],
      onRequestPart: { _ in },
      onResponsePart: { _, _ in }
    )

    pipeline.receive(.metadata([:]))
    pipeline.receive(.message("foo"))
    pipeline.receive(.end)

    pipeline.send(.metadata([:]), promise: nil)
    pipeline.send(.message("bar", .init(compress: false, flush: false)), promise: nil)
    pipeline.send(.end(.ok, [:]), promise: nil)

    // Check the request parts are there.
    assertThat(recorder.requestParts, .hasCount(3))
    assertThat(recorder.requestParts[0].metadata, .is(.notNil()))
    assertThat(recorder.requestParts[1].message, .is(.notNil()))
    assertThat(recorder.requestParts[2].isEnd, .is(true))

    // Check the response parts are there.
    assertThat(recorder.responseParts, .hasCount(3))
    assertThat(recorder.responseParts[0].metadata, .is(.notNil()))
    assertThat(recorder.responseParts[1].message, .is(.notNil()))
    assertThat(recorder.responseParts[2].end, .is(.notNil()))
  }
}

internal class RecordingServerInterceptor<Request, Response>:
  ServerInterceptor<Request, Response> {
  var requestParts: [GRPCServerRequestPart<Request>] = []
  var responseParts: [GRPCServerResponsePart<Response>] = []

  override func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    self.requestParts.append(part)
    context.receive(part)
  }

  override func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    context: ServerInterceptorContext<Request, Response>
  ) {
    self.responseParts.append(part)
    context.send(part, promise: promise)
  }
}

extension GRPCServerRequestPart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(metadata):
      return metadata
    default:
      return nil
    }
  }

  var message: Request? {
    switch self {
    case let .message(message):
      return message
    default:
      return nil
    }
  }

  var isEnd: Bool {
    switch self {
    case .end:
      return true
    default:
      return false
    }
  }
}

extension GRPCServerResponsePart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(metadata):
      return metadata
    default:
      return nil
    }
  }

  var message: Response? {
    switch self {
    case let .message(message, _):
      return message
    default:
      return nil
    }
  }

  var end: (GRPCStatus, HPACKHeaders)? {
    switch self {
    case let .end(status, trailers):
      return (status, trailers)
    default:
      return nil
    }
  }
}
