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

/// An RPC service which can register its methods with an ``RPCRouter``.
///
/// You typically won't have to implement this protocol yourself as the generated service code
/// provides conformance for your generated service type. However, if you need to customise which
/// methods your service offers or how the methods are registered then you can override the
/// generated conformance by implementing ``registerMethods(with:)`` manually by calling
/// ``RPCRouter/registerHandler(forMethod:deserializer:serializer:handler:)`` for each method
/// you want to register with the router.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public protocol RegistrableRPCService: Sendable {
  /// Registers methods to server with the provided ``RPCRouter``.
  ///
  /// - Parameter router: The router to register methods with.
  func registerMethods(with router: inout RPCRouter)
}
