/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

/// A bidirectional communication channel between a client and server for a given method.
@available(gRPCSwift 2.0, *)
public struct RPCStream<
  Inbound: AsyncSequence & Sendable,
  Outbound: ClosableRPCWriterProtocol & Sendable
>: Sendable {
  /// Information about the method this stream is for.
  public var descriptor: MethodDescriptor

  /// A sequence of messages received from the network.
  public var inbound: Inbound

  /// A writer for messages sent across the network.
  public var outbound: Outbound

  public init(descriptor: MethodDescriptor, inbound: Inbound, outbound: Outbound) {
    self.descriptor = descriptor
    self.inbound = inbound
    self.outbound = outbound
  }
}
