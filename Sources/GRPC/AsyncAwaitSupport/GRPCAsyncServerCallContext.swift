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
#if compiler(>=5.6)

import Logging
import NIOConcurrencyHelpers
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncServerCallContext: Sendable {
  @usableFromInline
  let contextProvider: AsyncServerCallContextProvider

  /// Details of the request, including request headers and a logger.
  public var request: Request

  /// A response context which may be used to set response headers and trailers.
  public var response: Response {
    Response(contextProvider: self.contextProvider)
  }

  /// Access the ``UserInfo`` dictionary which is shared with the interceptor contexts for this RPC.
  ///
  /// - Important: While ``UserInfo`` has value-semantics, this function accesses a reference
  ///   wrapped ``UserInfo``. The contexts passed to interceptors provide the same reference. As such
  ///   this may be used as a mechanism to pass information between interceptors and service
  ///   providers.
  public func withUserInfo<Result: Sendable>(
    _ body: @Sendable @escaping (UserInfo) throws -> Result
  ) async throws -> Result {
    return try await self.contextProvider.withUserInfo(body)
  }

  /// Modify the ``UserInfo`` dictionary which is shared with the interceptor contexts for this RPC.
  ///
  /// - Important: While ``UserInfo`` has value-semantics, this function accesses a reference
  ///   wrapped ``UserInfo``. The contexts passed to interceptors provide the same reference. As such
  ///   this may be used as a mechanism to pass information between interceptors and service
  ///   providers.
  public func withMutableUserInfo<Result: Sendable>(
    _ modify: @Sendable @escaping (inout UserInfo) -> Result
  ) async throws -> Result {
    return try await self.contextProvider.withMutableUserInfo(modify)
  }

  @inlinable
  internal init(
    headers: HPACKHeaders,
    logger: Logger,
    contextProvider: AsyncServerCallContextProvider
  ) {
    self.request = Request(headers: headers, logger: logger)
    self.contextProvider = contextProvider
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncServerCallContext {
  public struct Request: Sendable {
    /// The request headers received from the client at the start of the RPC.
    public var headers: HPACKHeaders

    /// A logger.
    public var logger: Logger

    @usableFromInline
    init(headers: HPACKHeaders, logger: Logger) {
      self.headers = headers
      self.logger = logger
    }
  }

  public struct Response: Sendable {
    private let contextProvider: AsyncServerCallContextProvider

    /// Set the metadata to return at the start of the RPC.
    ///
    /// - Important: If this is required it should be updated _before_ the first response is sent
    ///   via the response stream writer. Updates must not be made after the first response has
    ///   been sent.
    public func setHeaders(_ headers: HPACKHeaders) async throws {
      try await self.contextProvider.setResponseHeaders(headers)
    }

    /// Set the metadata to return at the end of the RPC.
    ///
    /// If this is required it must be updated before returning from the handler.
    public func setTrailers(_ trailers: HPACKHeaders) async throws {
      try await self.contextProvider.setResponseTrailers(trailers)
    }

    /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
    /// this value to take effect compression must have been enabled on the server and a compression
    /// algorithm must have been negotiated with the client.
    public func compressResponses(_ compress: Bool) async throws {
      try await self.contextProvider.setResponseCompression(compress)
    }

    @usableFromInline
    internal init(contextProvider: AsyncServerCallContextProvider) {
      self.contextProvider = contextProvider
    }
  }
}

#endif
