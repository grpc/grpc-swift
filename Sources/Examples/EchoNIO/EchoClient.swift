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
import SwiftGRPCNIO
import NIO


class EchoClient: GRPCClientWrapper {

  let client: GRPCClient
  let service = "echo.Echo"

  init(client: GRPCClient) {
    self.client = client
  }

  func get(request: Echo_EchoRequest, callOptions: CallOptions? = nil) -> UnaryClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return UnaryClientCall(client: client, path: path(forMethod: "Get"), request: request, callOptions: callOptions ?? defaultCallOptions())
  }

  func expand(request: Echo_EchoRequest, callOptions: CallOptions? = nil, handler: @escaping (Echo_EchoResponse) -> Void) -> ServerStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return ServerStreamingClientCall(client: client, path: path(forMethod: "Expand"), request: request, callOptions: callOptions ?? defaultCallOptions(), handler: handler)
  }

  func collect(callOptions: CallOptions? = nil) -> ClientStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return ClientStreamingClientCall(client: client, path: path(forMethod: "Collect"), callOptions: callOptions ?? defaultCallOptions())
  }

  func update(callOptions: CallOptions? = nil, handler: @escaping (Echo_EchoResponse) -> Void) -> BidirectionalStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return BidirectionalStreamingClientCall(client: client, path: path(forMethod: "Update"), callOptions: callOptions ?? defaultCallOptions(), handler: handler)
  }
}
