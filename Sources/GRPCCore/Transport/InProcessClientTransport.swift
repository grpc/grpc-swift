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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// An in-process implementation of a ``ClientTransport``.
public struct InProcessClientTransport: ClientTransport {
  public typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  public typealias Outbound = RPCWriter<RPCRequestPart>.Closable
  
  public var retryThrottle: RetryThrottle
  
  private var executionConfigurations: ClientRPCExecutionConfigurationCollection
  
  public init() {
    self.retryThrottle = .init(maximumTokens: 10, tokenRatio: 0.1)
  }
  
  public func connect(lazily: Bool) async throws {
    <#code#>
  }
  
  public func close() {
    <#code#>
  }
  
  public func openStream(descriptor: MethodDescriptor) async throws -> RPCStream<Inbound, Outbound> {
    
  }
  
  public func executionConfiguration(forMethod descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration? {
    self.executionConfiguration(forMethod: descriptor)
  }
}
