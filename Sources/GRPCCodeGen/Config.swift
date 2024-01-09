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
public struct Configuration: Sendable {
  public var visibility: Visibility
  public var indentation: Int
  public var client: Bool
  public var server: Bool

  public struct Visibility: Sendable {
    internal var level: Level
    internal enum Level {
      case `internal`
      case `public`
      case `private`
      case `package`
      case `fileprivate`
    }
    public static var `internal`: Self { Self(level: .`internal`) }
    public static var `public`: Self { Self(level: .`public`) }
    public static var `private`: Self { Self(level: .`private`) }
    public static var `package`: Self { Self(level: .`package`) }
    public static var `fileprivate`: Self { Self(level: .`fileprivate`) }
  }
}
