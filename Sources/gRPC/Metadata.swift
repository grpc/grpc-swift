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

/// An item of metadata
private struct MetadataPair {
  var key: String
  var value: String
  init(key: String, value: String) {
    self.key = key
    self.value = value
  }
}

/// Metadata sent with gRPC messages
public class Metadata: CustomStringConvertible, NSCopying {
  /// Pointer to underlying C representation
  var underlyingArray: UnsafeMutableRawPointer
  
  init(underlyingArray: UnsafeMutableRawPointer) {
    self.underlyingArray = underlyingArray
  }
  
  public init() {
    underlyingArray = cgrpc_metadata_array_create()
  }
  
  public init(_ pairs: [[String: String]]) {
    underlyingArray = cgrpc_metadata_array_create()
    for pair in pairs {
      for key in pair.keys {
        if let value = pair[key] {
          add(key: key, value: value)
        }
      }
    }
  }
  
  public init(_ pairs: [String: String]) {
    underlyingArray = cgrpc_metadata_array_create()
    for key in pairs.keys {
      if let value = pairs[key] {
        add(key: key, value: value)
      }
    }
  }
  
  deinit {
    cgrpc_metadata_array_destroy(underlyingArray)
  }
  
  public func count() -> Int {
    return cgrpc_metadata_array_get_count(underlyingArray)
  }
  
  public func key(_ index: Int) -> String {
    if let string = cgrpc_metadata_array_copy_key_at_index(underlyingArray, index) {
      defer {
        cgrpc_free_copied_string(string)
      }
      if let key = String(cString: string, encoding: String.Encoding.utf8) {
        return key
      }
    }
    return "<binary-metadata-key>"
  }
  
  public func value(_ index: Int) -> String {
    if let string = cgrpc_metadata_array_copy_value_at_index(underlyingArray, index) {
      defer {
        cgrpc_free_copied_string(string)
      }
      if let value = String(cString: string, encoding: String.Encoding.utf8) {
        return value
      }
    }
    return "<binary-metadata-value>"
  }
  
  public func add(key: String, value: String) {
    cgrpc_metadata_array_append_metadata(underlyingArray, key, value)
  }
  
  public var description: String {
    var result = ""
    for i in 0..<count() {
      let key = self.key(i)
      let value = self.value(i)
      result += key + ":" + value + "\n"
    }
    return result
  }
  
  public func copy(with _: NSZone? = nil) -> Any {
    let copy = Metadata()
    for i in 0..<count() {
      copy.add(key: key(i), value: value(i))
    }
    return copy
  }
}
