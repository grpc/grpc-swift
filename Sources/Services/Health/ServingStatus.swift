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

/// The status of a service.
///
/// - ``ServingStatus/serving`` indicates that a service is healthy.
/// - ``ServingStatus/notServing`` indicates that a service is unhealthy.
public struct ServingStatus: Sendable, Hashable {
  internal enum Value: Sendable, Hashable {
    case serving
    case notServing
  }

  /// A status indicating that a service is healthy.
  public static let serving = ServingStatus(.serving)

  /// A status indicating that a service unhealthy.
  public static let notServing = ServingStatus(.notServing)

  internal var value: Value

  private init(_ value: Value) {
    self.value = value
  }
}
