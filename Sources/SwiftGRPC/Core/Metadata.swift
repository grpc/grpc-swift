/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation // for String.Encoding

/// Metadata sent with gRPC messages
public class Metadata: CustomStringConvertible {
  /// Pointer to underlying C representation
  let underlyingArray: UnsafeMutableRawPointer

  init(underlyingArray: UnsafeMutableRawPointer) {
    self.underlyingArray = underlyingArray
  }

  public init() {
    underlyingArray = cgrpc_metadata_array_create()
  }

  public init(_ pairs: [String: String]) {
    underlyingArray = cgrpc_metadata_array_create()
    for (key, value) in pairs {
      add(key: key, value: value)
    }
  }

  deinit {
    cgrpc_metadata_array_destroy(underlyingArray)
  }

  public func count() -> Int {
    return cgrpc_metadata_array_get_count(underlyingArray)
  }
  
  // Returns `nil` for non-UTF8 metadata key strings.
  public func key(_ index: Int) -> String? {
    // We actually know that this method will never return nil,
    // so we can forcibly unwrap the result. (Also below.)
    let keyData = cgrpc_metadata_array_copy_key_at_index(underlyingArray, index)!
    defer { cgrpc_free_copied_string(keyData) }
    return String(cString: keyData, encoding: String.Encoding.utf8)
  }
  
  // Returns `nil` for non-UTF8 metadata value strings.
  public func value(_ index: Int) -> String? {
    // We actually know that this method will never return nil,
    // so we can forcibly unwrap the result. (Also below.)
    let valueData = cgrpc_metadata_array_copy_value_at_index(underlyingArray, index)!
    defer { cgrpc_free_copied_string(valueData) }
    return String(cString: valueData, encoding: String.Encoding.utf8)
  }
  
  public func add(key: String, value: String) {
    cgrpc_metadata_array_append_metadata(underlyingArray, key, value)
  }
  
  public var description: String {
    var lines: [String] = []
    for i in 0..<count() {
      let key = self.key(i)
      let value = self.value(i)
      lines.append((key ?? "(nil)") + ":" + (value ?? "(nil)"))
    }
    return lines.joined(separator: "\n")
  }
  
  public func copy() -> Metadata {
    let copy = Metadata()
    for index in 0..<count() {
      let keyData = cgrpc_metadata_array_copy_key_at_index(underlyingArray, index)!
      defer { cgrpc_free_copied_string(keyData) }
      let valueData = cgrpc_metadata_array_copy_value_at_index(underlyingArray, index)!
      defer { cgrpc_free_copied_string(valueData) }
      cgrpc_metadata_array_append_metadata(copy.underlyingArray, keyData, valueData)
    }
    return copy
  }
}
