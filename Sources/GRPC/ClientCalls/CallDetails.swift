/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

internal struct CallDetails {
  /// The type of the RPC, e.g. unary.
  internal var type: GRPCCallType

  /// The path of the RPC used for the ":path" pseudo header, e.g. "/echo.Echo/Get"
  internal var path: String

  /// The host, used for the ":authority" pseudo header.
  internal var authority: String

  /// Value used for the ":scheme" pseudo header, e.g. "https".
  internal var scheme: String

  /// Call options provided by the user.
  internal var options: CallOptions
}
