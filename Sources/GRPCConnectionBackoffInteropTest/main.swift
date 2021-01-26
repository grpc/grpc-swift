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
import ArgumentParser
import Foundation
import GRPC
import GRPCInteroperabilityTestModels
import Logging
import NIO

// Notes from the test procedure are inline.
// See: https://github.com/grpc/grpc/blob/master/doc/connection-backoff-interop-test-description.md

// MARK: - Setup

// Since this is a long running test, print connectivity state changes to stdout with timestamps.
// We'll redirect logs to stderr so that stdout contains information only relevant to the test.
class PrintingConnectivityStateDelegate: ConnectivityStateDelegate {
  func connectivityStateDidChange(from oldState: ConnectivityState,
                                  to newState: ConnectivityState) {
    print("[\(Date())] connectivity state change: \(oldState) → \(newState)")
  }
}

func runTest(controlPort: Int, retryPort: Int) throws {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  defer {
    try! group.syncShutdownGracefully()
  }

  // MARK: - Test Procedure

  print("[\(Date())] Starting connection backoff interoperability test...")

  // 1. Call 'Start' on server control port with a large deadline or no deadline, wait for it to
  //    finish and check it succeeded.
  let controlConnection = ClientConnection.insecure(group: group)
    .connect(host: "localhost", port: controlPort)
  let controlClient = Grpc_Testing_ReconnectServiceClient(channel: controlConnection)
  print("[\(Date())] Control 'Start' call started")
  let controlStart = controlClient.start(.init(), callOptions: .init(timeLimit: .none))
  let controlStartStatus = try controlStart.status.wait()
  assert(controlStartStatus.code == .ok, "Control Start rpc failed: \(controlStartStatus.code)")
  print("[\(Date())] Control 'Start' call succeeded")

  // 2. Initiate a channel connection to server retry port, which should perform reconnections with
  //    proper backoffs. A convenient way to achieve this is to call 'Start' with a deadline of 540s.
  //    The rpc should fail with deadline exceeded.
  print("[\(Date())] Retry 'Start' call started")
  let retryConnection = ClientConnection.secure(group: group)
    .withConnectivityStateDelegate(PrintingConnectivityStateDelegate())
    .connect(host: "localhost", port: retryPort)
  let retryClient = Grpc_Testing_ReconnectServiceClient(
    channel: retryConnection,
    defaultCallOptions: CallOptions(timeLimit: .timeout(.seconds(540)))
  )
  let retryStart = retryClient.start(.init())
  // We expect this to take some time!
  let retryStartStatus = try retryStart.status.wait()
  assert(
    retryStartStatus.code == .deadlineExceeded,
    "Retry Start rpc status was not 'deadlineExceeded': \(retryStartStatus.code)"
  )
  print("[\(Date())] Retry 'Start' call terminated with expected status")

  // 3. Call 'Stop' on server control port and check it succeeded.
  print("[\(Date())] Control 'Stop' call started")
  let controlStop = controlClient.stop(.init())
  let controlStopStatus = try controlStop.status.wait()
  assert(controlStopStatus.code == .ok, "Control Stop rpc failed: \(controlStopStatus.code)")
  print("[\(Date())] Control 'Stop' call succeeded")

  // 4. Check the response to see whether the server thinks the backoffs passed the test.
  let controlResponse = try controlStop.response.wait()
  assert(controlResponse.passed, "TEST FAILED")
  print("[\(Date())] TEST PASSED")

  // MARK: - Tear down

  // Close the connections.

  // We expect close to fail on the retry connection because the channel should never be successfully
  // started.
  print("[\(Date())] Closing Retry connection")
  try? retryConnection.close().wait()
  print("[\(Date())] Closing Control connection")
  try controlConnection.close().wait()
}

struct ConnectionBackoffInteropTest: ParsableCommand {
  @Option
  var controlPort: Int

  @Option
  var retryPort: Int

  func run() throws {
    try runTest(controlPort: self.controlPort, retryPort: self.retryPort)
  }
}

ConnectionBackoffInteropTest.main()
