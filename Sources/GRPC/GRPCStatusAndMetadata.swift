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
import NIOHPACK
import NIOHTTP1

/// A simple struct holding a ``GRPCStatus`` and optionally trailers in the form of
/// `HPACKHeaders`.
public struct GRPCStatusAndTrailers: Equatable {
  /// The status.
  public var status: GRPCStatus

  /// The trailers.
  public var trailers: HPACKHeaders?

  public init(status: GRPCStatus, trailers: HPACKHeaders? = nil) {
    self.status = status
    self.trailers = trailers
  }
}
