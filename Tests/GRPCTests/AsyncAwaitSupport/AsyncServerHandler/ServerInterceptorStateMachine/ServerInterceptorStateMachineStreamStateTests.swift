/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

import XCTest

@testable import GRPC

internal final class ServerInterceptorStateMachineStreamStateTests: GRPCTestCase {
  func testInboundStreamState_receiveMetadataWhileIdle() {
    var state = ServerInterceptorStateMachine.InboundStreamState.idle
    XCTAssertEqual(state.receiveMetadata(), .accept)
    XCTAssertEqual(state, .receivingMessages)
  }

  func testInboundStreamState_receiveMessageWhileIdle() {
    let state = ServerInterceptorStateMachine.InboundStreamState.idle
    XCTAssertEqual(state.receiveMessage(), .reject)
    XCTAssertEqual(state, .idle)
  }

  func testInboundStreamState_receiveEndWhileIdle() {
    var state = ServerInterceptorStateMachine.InboundStreamState.idle
    XCTAssertEqual(state.receiveEnd(), .accept)
    XCTAssertEqual(state, .done)
  }

  func testInboundStreamState_receiveMetadataWhileReceivingMessages() {
    var state = ServerInterceptorStateMachine.InboundStreamState.receivingMessages
    XCTAssertEqual(state.receiveMetadata(), .reject)
    XCTAssertEqual(state, .receivingMessages)
  }

  func testInboundStreamState_receiveMessageWhileReceivingMessages() {
    let state = ServerInterceptorStateMachine.InboundStreamState.receivingMessages
    XCTAssertEqual(state.receiveMessage(), .accept)
    XCTAssertEqual(state, .receivingMessages)
  }

  func testInboundStreamState_receiveEndWhileReceivingMessages() {
    var state = ServerInterceptorStateMachine.InboundStreamState.receivingMessages
    XCTAssertEqual(state.receiveEnd(), .accept)
    XCTAssertEqual(state, .done)
  }

  func testInboundStreamState_receiveMetadataWhileDone() {
    var state = ServerInterceptorStateMachine.InboundStreamState.done
    XCTAssertEqual(state.receiveMetadata(), .reject)
    XCTAssertEqual(state, .done)
  }

  func testInboundStreamState_receiveMessageWhileDone() {
    let state = ServerInterceptorStateMachine.InboundStreamState.done
    XCTAssertEqual(state.receiveMessage(), .reject)
    XCTAssertEqual(state, .done)
  }

  func testInboundStreamState_receiveEndWhileDone() {
    var state = ServerInterceptorStateMachine.InboundStreamState.done
    XCTAssertEqual(state.receiveEnd(), .reject)
    XCTAssertEqual(state, .done)
  }

  func testOutboundStreamState_sendMetadataWhileIdle() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.idle
    XCTAssertEqual(state.sendMetadata(), .accept)
    XCTAssertEqual(state, .writingMessages)
  }

  func testOutboundStreamState_sendMessageWhileIdle() {
    let state = ServerInterceptorStateMachine.OutboundStreamState.idle
    XCTAssertEqual(state.sendMessage(), .reject)
    XCTAssertEqual(state, .idle)
  }

  func testOutboundStreamState_sendEndWhileIdle() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.idle
    XCTAssertEqual(state.sendEnd(), .accept)
    XCTAssertEqual(state, .done)
  }

  func testOutboundStreamState_sendMetadataWhileReceivingMessages() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.writingMessages
    XCTAssertEqual(state.sendMetadata(), .reject)
    XCTAssertEqual(state, .writingMessages)
  }

  func testOutboundStreamState_sendMessageWhileReceivingMessages() {
    let state = ServerInterceptorStateMachine.OutboundStreamState.writingMessages
    XCTAssertEqual(state.sendMessage(), .accept)
    XCTAssertEqual(state, .writingMessages)
  }

  func testOutboundStreamState_sendEndWhileReceivingMessages() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.writingMessages
    XCTAssertEqual(state.sendEnd(), .accept)
    XCTAssertEqual(state, .done)
  }

  func testOutboundStreamState_sendMetadataWhileDone() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.done
    XCTAssertEqual(state.sendMetadata(), .reject)
    XCTAssertEqual(state, .done)
  }

  func testOutboundStreamState_sendMessageWhileDone() {
    let state = ServerInterceptorStateMachine.OutboundStreamState.done
    XCTAssertEqual(state.sendMessage(), .reject)
    XCTAssertEqual(state, .done)
  }

  func testOutboundStreamState_sendEndWhileDone() {
    var state = ServerInterceptorStateMachine.OutboundStreamState.done
    XCTAssertEqual(state.sendEnd(), .reject)
    XCTAssertEqual(state, .done)
  }
}
