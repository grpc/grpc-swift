/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import GRPC
import NIO
import XCTest

class ClientClosedChannelTests: EchoTestCaseBase {
  func testUnaryOnClosedConnection() throws {
    let initialMetadataExpectation = self.makeInitialMetadataExpectation()
    let responseExpectation = self.makeResponseExpectation()
    let statusExpectation = self.makeStatusExpectation()

    self.client.channel.close().map {
      self.client.get(Echo_EchoRequest(text: "foo"))
    }.whenSuccess { get in
      get.initialMetadata.assertError(fulfill: initialMetadataExpectation)
      get.response.assertError(fulfill: responseExpectation)
      get.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)
    }

    self.wait(
      for: [initialMetadataExpectation, responseExpectation, statusExpectation],
      timeout: self.defaultTestTimeout
    )
  }

  func testClientStreamingOnClosedConnection() throws {
    let initialMetadataExpectation = self.makeInitialMetadataExpectation()
    let responseExpectation = self.makeResponseExpectation()
    let statusExpectation = self.makeStatusExpectation()

    self.client.channel.close().map {
      self.client.collect()
    }.whenSuccess { collect in
      collect.initialMetadata.assertError(fulfill: initialMetadataExpectation)
      collect.response.assertError(fulfill: responseExpectation)
      collect.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)
    }

    self.wait(
      for: [initialMetadataExpectation, responseExpectation, statusExpectation],
      timeout: self.defaultTestTimeout
    )
  }

  func testClientStreamingWhenConnectionIsClosedBetweenMessages() throws {
    let statusExpectation = self.makeStatusExpectation()
    let responseExpectation = self.makeResponseExpectation()
    let requestExpectation = self.makeRequestExpectation(expectedFulfillmentCount: 3)

    let collect = self.client.collect()

    collect.sendMessage(Echo_EchoRequest(text: "foo")).peek {
      requestExpectation.fulfill()
    }.flatMap {
      collect.sendMessage(Echo_EchoRequest(text: "bar"))
    }.peek {
      requestExpectation.fulfill()
    }.flatMap {
      self.client.channel.close()
    }.peekError { error in
      XCTFail("Encountered error before or during closing the connection: \(error)")
    }.flatMap {
      collect.sendMessage(Echo_EchoRequest(text: "baz"))
    }.assertError(fulfill: requestExpectation)

    collect.response.assertError(fulfill: responseExpectation)
    collect.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)

    self.wait(
      for: [statusExpectation, responseExpectation, requestExpectation],
      timeout: self.defaultTestTimeout
    )
  }

  func testServerStreamingOnClosedConnection() throws {
    let initialMetadataExpectation = self.makeInitialMetadataExpectation()
    let statusExpectation = self.makeStatusExpectation()

    self.client.channel.close().map {
      self.client.expand(Echo_EchoRequest(text: "foo")) { response in
        XCTFail("No response expected but got: \(response)")
      }
    }.whenSuccess { expand in
      expand.initialMetadata.assertError(fulfill: initialMetadataExpectation)
      expand.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)
    }

    self.wait(
      for: [initialMetadataExpectation, statusExpectation],
      timeout: self.defaultTestTimeout
    )
  }

  func testBidirectionalStreamingOnClosedConnection() throws {
    let initialMetadataExpectation = self.makeInitialMetadataExpectation()
    let statusExpectation = self.makeStatusExpectation()

    self.client.channel.close().map {
      self.client.update { response in
        XCTFail("No response expected but got: \(response)")
      }
    }.whenSuccess { update in
      update.initialMetadata.assertError(fulfill: initialMetadataExpectation)
      update.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)
    }

    self.wait(
      for: [initialMetadataExpectation, statusExpectation],
      timeout: self.defaultTestTimeout
    )
  }

  func testBidirectionalStreamingWhenConnectionIsClosedBetweenMessages() throws {
    let statusExpectation = self.makeStatusExpectation()
    let requestExpectation = self.makeRequestExpectation(expectedFulfillmentCount: 3)

    // We can't make any assertions about the number of responses we will receive before closing
    // the connection; just ignore all responses.
    let update = self.client.update { _ in }

    update.sendMessage(Echo_EchoRequest(text: "foo")).peek {
      requestExpectation.fulfill()
    }.flatMap {
      update.sendMessage(Echo_EchoRequest(text: "bar"))
    }.peek {
      requestExpectation.fulfill()
    }.flatMap {
      self.client.channel.close()
    }.peekError { error in
      XCTFail("Encountered error before or during closing the connection: \(error)")
    }.flatMap {
      update.sendMessage(Echo_EchoRequest(text: "baz"))
    }.assertError(fulfill: requestExpectation)

    update.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)

    self.wait(for: [statusExpectation, requestExpectation], timeout: self.defaultTestTimeout)
  }

  func testBidirectionalStreamingWithNoPromiseWhenConnectionIsClosedBetweenMessages() throws {
    let statusExpectation = self.makeStatusExpectation()

    let update = self.client.update { response in
      XCTFail("No response expected but got: \(response)")
    }

    update.sendMessage(.with { $0.text = "0" }).flatMap {
      self.client.channel.close()
    }.whenSuccess {
      update.sendMessage(.with { $0.text = "1" }, promise: nil)
    }

    update.status.map { $0.code }.assertEqual(.unavailable, fulfill: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.defaultTestTimeout)
  }
}
