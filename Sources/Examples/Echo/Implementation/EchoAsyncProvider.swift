/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.5)
import EchoModel
import GRPC

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public final class EchoAsyncProvider: Echo_EchoAsyncProvider {
  public let interceptors: Echo_EchoServerInterceptorFactoryProtocol?

  public init(interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil) {
    self.interceptors = interceptors
  }

  public func get(
    request: Echo_EchoRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Echo_EchoResponse {
    return .with {
      $0.text = "Swift echo get: " + request.text
    }
  }

  public func expand(
    request: Echo_EchoRequest,
    responseStream: GRPCAsyncResponseStreamWriter<Echo_EchoResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for (i, part) in request.text.components(separatedBy: " ").lazy.enumerated() {
      try await responseStream.send(.with { $0.text = "Swift echo expand (\(i)): \(part)" })
    }
  }

  public func collect(
    requests: GRPCAsyncRequestStream<Echo_EchoRequest>,
    context: GRPCAsyncServerCallContext
  ) async throws -> Echo_EchoResponse {
    let text = try await requests.reduce(into: "Swift echo collect:") { result, request in
      result += " \(request.text)"
    }

    return .with { $0.text = text }
  }

  public func update(
    requests: GRPCAsyncRequestStream<Echo_EchoRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Echo_EchoResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    var counter = 0
    for try await request in requests {
      let text = "Swift echo update (\(counter)): \(request.text)"
      try await responseStream.send(.with { $0.text = text })
      counter += 1
    }
  }
}

#endif // compiler(>=5.5)
