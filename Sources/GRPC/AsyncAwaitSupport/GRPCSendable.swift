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

import NIOCore

#if compiler(>=5.6)
public typealias GRPCSendable = Swift.Sendable
#else
public typealias GRPCSendable = Any
#endif // compiler(>=5.6)

#if compiler(>=5.6)
@preconcurrency
public protocol GRPCPreconcurrencySendable: Sendable {}
#else
public protocol GRPCPreconcurrencySendable {}
#endif // compiler(>=5.6)

#if compiler(>=5.6)
@preconcurrency public typealias GRPCChannelInitializer = @Sendable (Channel)
  -> EventLoopFuture<Void>
#else
public typealias GRPCChannelInitializer = (Channel) -> EventLoopFuture<Void>
#endif // compiler(>=5.6)
