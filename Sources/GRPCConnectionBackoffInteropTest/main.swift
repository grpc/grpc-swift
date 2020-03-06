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
import Foundation
import GRPC
import GRPCInteroperabilityTestModels
import NIO
import Logging

let args = CommandLine.arguments
guard args.count == 3, let controlPort = Int(args[1]), let retryPort = Int(args[2]) else {
  print("Usage: \(args[0]) <server_control_port> <server_retry_port>")
  exit(1)
}

// Notes from the test procedure are inline.
// See: https://github.com/grpc/grpc/blob/master/doc/connection-backoff-interop-test-description.md

// MARK: - Setup

// Since this is a long running test, print connectivity state changes to stdout with timestamps.
// We'll redirect logs to stderr so that stdout contains information only relevant to the test.
class PrintingConnectivityStateDelegate: ConnectivityStateDelegate {
  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
    print("[\(Date())] connectivity state change: \(oldState) → \(newState)")
  }
}

// Reduce stdout noise.
LoggingSystem.bootstrap(StreamLogHandler.standardError)

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
  try! group.syncShutdownGracefully()
}

// The client must connect to the control port without TLS.
let controlConfig = ClientConnection.Configuration(
  target: .hostAndPort("localhost", controlPort),
  eventLoopGroup: group,
  connectionBackoff: .init()
)

// The client must connect to the retry port with TLS.
let retryConfig = ClientConnection.Configuration(
  target: .hostAndPort("localhost", retryPort),
  eventLoopGroup: group,
  connectivityStateDelegate: PrintingConnectivityStateDelegate(),
  tls: .init(),
  connectionBackoff: .init()
)

// MARK: - Test Procedure

print("[\(Date())] Starting connection backoff interoperability test...")

// 1. Call 'Start' on server control port with a large deadline or no deadline, wait for it to
//    finish and check it succeeded.
let controlConnection = ClientConnection(configuration: controlConfig)
let controlClient = Grpc_Testing_ReconnectServiceClient(channel: controlConnection)
print("[\(Date())] Control 'Start' call started")
let controlStart = controlClient.start(.init(), callOptions: .init(timeout: .infinite))
let controlStartStatus = try controlStart.status.wait()
assert(controlStartStatus.code == .ok, "Control Start rpc failed: \(controlStartStatus.code)")
print("[\(Date())] Control 'Start' call succeeded")

// 2. Initiate a channel connection to server retry port, which should perform reconnections with
//    proper backoffs. A convenient way to achieve this is to call 'Start' with a deadline of 540s.
//    The rpc should fail with deadline exceeded.
print("[\(Date())] Retry 'Start' call started")
let retryConnection = ClientConnection(configuration: retryConfig)
let retryClient = Grpc_Testing_ReconnectServiceClient(
  channel: retryConnection,
  defaultCallOptions: CallOptions(timeout: try! .seconds(540))
)
let retryStart = retryClient.start(.init())
// We expect this to take some time!
let retryStartStatus = try retryStart.status.wait()
assert(retryStartStatus.code == .deadlineExceeded,
       "Retry Start rpc status was not 'deadlineExceeded': \(retryStartStatus.code)")
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
