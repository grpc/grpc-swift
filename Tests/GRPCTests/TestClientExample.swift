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
import EchoModel
import EchoImplementation
import GRPC
import NIO
import XCTest

class FakeResponseStreamExampleTests: GRPCTestCase {
  var client: Echo_EchoTestClient!

  override func setUp() {
    super.setUp()
    self.client = Echo_EchoTestClient()
  }

  func testUnary() {
    // Enqueue a Get response. This will be dequeued when the client makes the next Get RPC.
    //
    // We can also use a response stream, see 'testUnaryResponseStream'.
    self.client.enqueueGetResponse(.with { $0.text = "Bar!" })

    // Start the Get RPC.
    let get = self.client.get(.with { $0.text = "Foo!" })

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasGetResponsesRemaining)

    // Check the response values:
    XCTAssertEqual(try get.response.wait(), .with { $0.text = "Bar!" })
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())
  }

  func testUnaryResponseStream() {
    // Enqueue a Get response stream. This will be used for the next Get RPC and we can choose when
    // to send responses on it.
    let stream = self.client.makeGetResponseStream()

    // Start the Get RPC.
    let get = self.client.get(.with { $0.text = "Foo!" })

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasGetResponsesRemaining)

    // Now send the response on the stream we made.
    XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = "Bar!" }))

    // Check the response values:
    XCTAssertEqual(try get.response.wait(), .with { $0.text = "Bar!" })
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())
  }

  func testClientStreaming() {
    // Enqueue a Collect response. This will be dequeued when the client makes the next Collect RPC.
    //
    // We can also use a response stream, see 'testClientStreamingResponseStream'.
    self.client.enqueueCollectResponse(.with { $0.text = "Foo" })

    // Start the Collect RPC.
    let collect = self.client.collect()

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasCollectResponsesRemaining)

    XCTAssertEqual(try collect.response.wait(), .with { $0.text = "Foo" })
    XCTAssertTrue(try collect.status.map { $0.isOk }.wait())
  }

  func testClientStreamingResponseStream() {
    // Enqueue a Collect response stream. This will be used for the next Collect RPC and we can choose when
    // to send responses on it.
    let stream = self.client.makeCollectResponseStream()

    // Start the Collect RPC.
    let collect = self.client.collect()

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasCollectResponsesRemaining)

    // Send the response on the stream we made.
    XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = "Foo" }))

    XCTAssertEqual(try collect.response.wait(), .with { $0.text = "Foo" })
    XCTAssertTrue(try collect.status.map { $0.isOk }.wait())
  }

  func testServerStreaming() {
    // Enqueue some Expand responses. These will be dequeued when the client makes the next Expand RPC.
    //
    // We can also use a response stream, see 'testServerStreamingResponseStream'.
    let fooBarBaz = ["Foo", "Bar", "Baz"]
    self.client.enqueueExpandResponses(fooBarBaz.map { text in .with { $0.text = text }})

    // Start the 'Expand' RPC. We'll create a handler which records responses.
    //
    // Note that in normal applications this wouldn't be thread-safe since the response handler is
    // executed on a different thread; for the test client the calling thread is thread is the same
    // as the tread on which the RPC is called, i.e. this thread.
    var responses: [String] = []
    let expand = self.client.expand(.with { $0.text = "Hello!" }) { response in
      responses.append(response.text)
    }

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasExpandResponsesRemaining)

    XCTAssertTrue(try expand.status.map { $0.isOk }.wait())
    XCTAssertEqual(responses, fooBarBaz)
  }

  func testServerStreamingResponseStream() {
    // Enqueue an Expand response stream. This will be used for the next Expand RPC and we can choose
    // when to send responses on it.
    let stream = self.client.makeExpandResponseStream()

    // Start the 'Expand' RPC. We'll create a handler which records responses.
    //
    // Note that in normal applications this wouldn't be thread-safe since the response handler is
    // executed on a different thread; for the test client the calling thread is thread is the same
    // as the tread on which the RPC is called, i.e. this thread.
    var responses: [String] = []
    let expand = self.client.expand(.with { $0.text = "Hello!" }) { response in
      responses.append(response.text)
    }

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasExpandResponsesRemaining)

    // Send some responses.
    let fooBarBaz = ["Foo", "Bar", "Baz"]
    for message in fooBarBaz {
      XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = message }))
    }
    // Close the stream.
    XCTAssertNoThrow(try stream.sendEnd())

    XCTAssertTrue(try expand.status.map { $0.isOk }.wait())
    XCTAssertEqual(responses, fooBarBaz)
  }

  func testBidirectionalStreaming() {
    // Enqueue some Update responses. These will be dequeued when the client makes the next Update RPC.
    //
    // We can also use a response stream, see 'testBidirectionalStreamingResponseStream'.
    let fooBarBaz = ["Foo", "Bar", "Baz"]
    self.client.enqueueUpdateResponses(fooBarBaz.map { text in .with { $0.text = text }})

    // Start the 'Update' RPC. We'll create a handler which records responses.
    //
    // Note that in normal applications this wouldn't be thread-safe since the response handler is
    // executed on a different thread; for the test client the calling thread is thread is the same
    // as the tread on which the RPC is called, i.e. this thread.
    var responses: [String] = []
    let update = self.client.update { response in
      responses.append(response.text)
    }

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasUpdateResponsesRemaining)

    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
    XCTAssertEqual(responses, fooBarBaz)
  }

  func testBidirectionalStreamingResponseStream() {
    // Enqueue an Update response stream. This will be used for the next Update RPC and we can choose
    // when to send responses on it.
    let stream = self.client.makeUpdateResponseStream()

    // Start the 'Update' RPC. We'll create a handler which records responses.
    //
    // Note that in normal applications this wouldn't be thread-safe since the response handler is
    // executed on a different thread; for the test client the calling thread is thread is the same
    // as the tread on which the RPC is called, i.e. this thread.
    var responses: [String] = []
    let update = self.client.update { response in
      responses.append(response.text)
    }

    // The response stream has been consumed by the call.
    XCTAssertFalse(self.client.hasUpdateResponsesRemaining)

    // Send some responses.
    let fooBarBaz = ["Foo", "Bar", "Baz"]
    for message in fooBarBaz {
      XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = message }))
    }
    // Close the stream.
    XCTAssertNoThrow(try stream.sendEnd())

    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
    XCTAssertEqual(responses, fooBarBaz)
  }

}

// These tests demonstrate the finer grained control enabled by the response streams.
extension FakeResponseStreamExampleTests {
  func testUnaryWithTrailingMetadata() {
    // Create a response stream for the RPC.
    let getResponseStream = self.client.makeGetResponseStream()

    // Send the request.
    let get = self.client.get(.with { $0.text = "Hello!" })

    // Send the response as well as some trailing metadata.
    XCTAssertNoThrow(try getResponseStream.sendMessage(.with { $0.text = "Goodbye!" }, trailingMetadata: ["bar": "baz"]))

    // Check the response values:
    XCTAssertEqual(try get.response.wait(), .with { $0.text = "Goodbye!" })
    XCTAssertEqual(try get.trailingMetadata.wait(), ["bar": "baz"])
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())
  }

  func testUnaryError() {
    // Create a response stream for the RPC.
    let getResponseStream = self.client.makeGetResponseStream()

    // Send the request.
    let get = self.client.get(.with { $0.text = "Hello!" })

    // Respond with an error. We could send trailing metadata here as well.
    struct DummyError: Error {}
    XCTAssertNoThrow(try getResponseStream.sendError(DummyError()))

    // Check the response values:
    XCTAssertThrowsError(try get.response.wait()) { error in
      XCTAssertTrue(error is DummyError)
    }

    // We sent a dummy error; we could have sent a `GRPCStatus` error in which case we could assert
    // for equality here.
    XCTAssertFalse(try get.status.map { $0.isOk }.wait())
  }

  func testUnaryWithRequestHandler() {
    // Create a response stream for the RPC we want to make, we'll specify a *request* handler as well.
    let getResponseStream = self.client.makeGetResponseStream { requestPart in
      switch requestPart {
      case .metadata(let headers):
        XCTAssertTrue(headers.contains(name: "a-test-key"))

      case .message(let request):
        XCTAssertEqual(request, .with { $0.text = "Hello!" })

      case .end:
        ()
      }
    }

    // We'll send some custom metadata for the call as well. It will be validated above.
    let callOptions = CallOptions(customMetadata: ["a-test-key": "a test value"])
    let get = self.client.get(.with { $0.text = "Hello!" }, callOptions: callOptions)

    // Send the response.
    XCTAssertNoThrow(try getResponseStream.sendMessage(.with{ $0.text = "Goodbye!" }))
    XCTAssertEqual(try get.response.wait(), .with { $0.text = "Goodbye!" })
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())
  }

  func testUnaryResponseOrdering() {
    // Create a response stream for the RPC we want to make.
    let getResponseStream = self.client.makeGetResponseStream()

    // We can queue up the response *before* we make the RPC.
    XCTAssertNoThrow(try getResponseStream.sendMessage(.with { $0.text = "Goodbye!" }))

    // Start the RPC: the response will be sent automatically.
    let get = self.client.get(.with { $0.text = "Hello!" })

    // Check the response values.
    XCTAssertEqual(try get.response.wait(), .with { $0.text = "Goodbye!" })
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())
  }

  func testBidirectionalResponseOrdering() {
    // Create a response stream for the RPC we want to make.
    let updateResponseStream = self.client.makeUpdateResponseStream()

    // We can queue up responses *before* we make the RPC.
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "1" }))
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "2" }))

    // Start the RPC: the response will be sent automatically.
    var responses: [Echo_EchoResponse] = []
    let update = self.client.update { response in
      responses.append(response)
    }

    // We should have two responses already.
    XCTAssertEqual(responses.count, 2)

    // We can also send responses after starting the RPC.
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "3" }))

    // And interleave requests with responses.
    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "a" }).wait())
    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "b" }).wait())
    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "c" }).wait())
    XCTAssertNoThrow(try update.sendEnd().wait())

    // Send the final response and close.
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "4" }))
    XCTAssertNoThrow(try updateResponseStream.sendEnd())

    // Check the response values.
    let expected = (1...4).map { number in
      Echo_EchoResponse.with { $0.text = "\(number)" }
    }
    XCTAssertEqual(responses, expected)
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testBidirectionalStreamingSendAfterEnd() {
    // Enqueue the responses for Update.
    self.client.enqueueUpdateResponses([.with { $0.text = "Foo" }])

    // Start a call.
    let update = self.client.update { response in
      XCTAssertEqual(response, .with { $0.text = "Foo" })
    }

    // Since the RPC has already completed (the status promise has been fulfilled), send will fail.
    XCTAssertThrowsError(try update.sendMessage(.with { $0.text = "Kaboom!"}).wait())
    XCTAssertThrowsError(try update.sendEnd().wait())

    // The call completed *before* we tried to send "Kaboom!".
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testBidirectionalWithCustomInitialMetadata() {
    // Create a response stream for the RPC we want to make.
    let updateResponseStream = self.client.makeUpdateResponseStream()

    // Send back some initial metadata, response, and trailers.
    XCTAssertNoThrow(try updateResponseStream.sendInitialMetadata(["foo": "bar"]))
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "foo" }))
    XCTAssertNoThrow(try updateResponseStream.sendEnd(trailingMetadata: ["bar": "baz"]))

    // Start the RPC. We only expect one response so we'll validate it in the handler.
    let update = self.client.update { response in
      XCTAssertEqual(response, .with { $0.text = "foo" })
    }

    // Check the rest of the response part values.
    XCTAssertEqual(try update.initialMetadata.wait(), ["foo": "bar"])
    XCTAssertEqual(try update.trailingMetadata.wait(), ["bar": "baz"])
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testWriteAfterEndFails() {
    // Create a response stream for the RPC we want to make.
    let updateResponseStream = self.client.makeUpdateResponseStream()

    // Start the RPC.
    let update = self.client.update { response in
      XCTFail("Unexpected response: \(response)")
    }

    // Send a message and end.
    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "1" }).wait())
    XCTAssertNoThrow(try update.sendEnd().wait())

    // Send another message, the write should fail.
    XCTAssertThrowsError(try update.sendMessage(.with { $0.text = "Too late!" }).wait()) { error in
      XCTAssertEqual(error as? ChannelError, .ioOnClosedChannel)
    }

    // Send close from the server.
    XCTAssertNoThrow(try updateResponseStream.sendEnd())
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testWeGetAllRequestParts() {
    var requestParts: [FakeRequestPart<Echo_EchoRequest>] = []
    let updateResponseStream = self.client.makeUpdateResponseStream { request in
      requestParts.append(request)
    }

    let update = self.client.update(callOptions: CallOptions(customMetadata: ["foo": "bar"])) {
      XCTFail("Unexpected response: \($0)")
    }

    update.sendMessage(.with { $0.text = "foo" }, promise: nil)
    update.sendEnd(promise: nil)

    // These should be ignored since we've already sent end.
    update.sendMessage(.with { $0.text = "bar" }, promise: nil)
    update.sendEnd(promise: nil)

    // Check the expected request parts.
    XCTAssertEqual(requestParts, [
      .metadata(["foo": "bar"]),
      .message(.with { $0.text = "foo" }),
      .end
    ])

    // Send close from the server.
    XCTAssertNoThrow(try updateResponseStream.sendEnd())
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testInitialMetadataIsSentAutomatically() {
    let updateResponseStream = self.client.makeUpdateResponseStream()
    let update = self.client.update { response in
      XCTAssertEqual(response, .with { $0.text = "foo" })
    }

    // Send a message and end. Initial metadata is explicitly not set but will be sent on our
    // behalf. It will be empty.
    XCTAssertNoThrow(try updateResponseStream.sendMessage(.with { $0.text = "foo" }))
    XCTAssertNoThrow(try updateResponseStream.sendEnd())

    // Metadata should be empty.
    XCTAssertEqual(try update.initialMetadata.wait(), [:])
    XCTAssertTrue(try update.status.map { $0.isOk }.wait())
  }

  func testMissingResponseStream() {
    // If no response stream is created for a call then it will fail with status code 'unavailable'.
    let get = self.client.get(.with { $0.text = "Uh oh!" })

    XCTAssertEqual(try get.status.map { $0.code }.wait(), .unavailable)
    XCTAssertThrowsError(try get.response.wait()) { error in
      guard let status = error as? GRPCStatus else {
        XCTFail("Expected a GRPCStatus, had the error was: \(error)")
        return
      }
      XCTAssertEqual(status.code, .unavailable)
    }
  }
}
