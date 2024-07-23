/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import GRPCCore

/// A registerable RPC service to probe whether a server is able to handle RPCs.
@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class HealthService: RegistrableRPCService {
  internal let service = InternalHealthService()

  public func registerMethods(with router: inout RPCRouter) {
    self.service.registerMethods(with: &router)
  }
}
