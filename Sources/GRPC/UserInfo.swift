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

/// `UserInfo` is a dictionary for heterogeneously typed values with type safe access to the stored
/// values.
///
/// `UserInfo` is shared between server interceptor contexts and server handlers, this is on a
/// per-RPC basis. `UserInfo` is *not* shared across a connection.
///
/// Values are keyed by a type conforming to the `UserInfo.Key` protocol. The protocol requires an
/// `associatedtype`: the type of the value the key is paired with. A key can be created using a
/// caseless `enum`, for example:
///
/// ```
/// enum IDKey: UserInfo.Key {
///   typealias Value = Int
/// }
/// ```
///
/// Values can be set and retrieved from `UserInfo` by subscripting with the key:
///
/// ```
/// userInfo[IDKey.self] = 42
/// let id = userInfo[IDKey.self]  // id = 42
///
/// userInfo[IDKey.self] = nil
/// ```
///
/// More convenient access can be provided with helper extensions on `UserInfo`:
///
/// ```
/// extension UserInfo {
///   var id: IDKey.Value? {
///     get { self[IDKey.self] }
///     set { self[IDKey.self] = newValue }
///   }
/// }
/// ```
public struct UserInfo: CustomStringConvertible {
  private var storage: [AnyUserInfoKey: Any]

  /// A protocol for a key.
  public typealias Key = UserInfoKey

  /// Create an empty 'UserInfo'.
  public init() {
    self.storage = [:]
  }

  /// Allows values to be set and retrieved in a type safe way.
  public subscript<Key: UserInfoKey>(key: Key.Type) -> Key.Value? {
    get {
      if let anyValue = self.storage[AnyUserInfoKey(key)] {
        // The types must line up here.
        return (anyValue as! Key.Value)
      } else {
        return nil
      }
    }
    set {
      self.storage[AnyUserInfoKey(key)] = newValue
    }
  }

  public var description: String {
    return "[" + self.storage.map { key, value in
      "\(key): \(value)"
    }.joined(separator: ", ") + "]"
  }

  /// A `UserInfoKey` wrapper.
  private struct AnyUserInfoKey: Hashable, CustomStringConvertible {
    private let keyType: Any.Type

    var description: String {
      return String(describing: self.keyType.self)
    }

    init<Key: UserInfoKey>(_ keyType: Key.Type) {
      self.keyType = keyType
    }

    static func == (lhs: AnyUserInfoKey, rhs: AnyUserInfoKey) -> Bool {
      return ObjectIdentifier(lhs.keyType) == ObjectIdentifier(rhs.keyType)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(self.keyType))
    }
  }
}

public protocol UserInfoKey {
  /// The type of identified by this key.
  associatedtype Value
}
