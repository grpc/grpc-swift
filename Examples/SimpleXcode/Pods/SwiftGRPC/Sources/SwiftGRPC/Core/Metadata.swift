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
public class Metadata {
  public enum Error: Swift.Error {
    /// Field ownership can only be transferred once. Likewise, it is not advisable to write to a metadata array whose
    /// fields we do not own.
    case doesNotOwnFields
  }
  
  /// Pointer to underlying C representation
  fileprivate let underlyingArray: UnsafeMutableRawPointer
  /// Ownership of the fields inside metadata arrays provided by `grpc_op_recv_initial_metadata` and
  /// `grpc_op_recv_status_on_client` is retained by the gRPC library. Similarly, passing metadata to gRPC for sending
  /// to the client for sending/receiving also transfers ownership. However, before we have passed that metadata to
  /// gRPC, we are still responsible for releasing its fields. This variable tracks that.
  fileprivate var ownsFields: Bool

  init(underlyingArray: UnsafeMutableRawPointer, ownsFields: Bool) {
    self.underlyingArray = underlyingArray
    self.ownsFields = ownsFields
  }

  public init() {
    underlyingArray = cgrpc_metadata_array_create()
    ownsFields = true
  }

  public init(_ pairs: [String: String]) throws {
    underlyingArray = cgrpc_metadata_array_create()
    ownsFields = true
    for (key, value) in pairs {
      try add(key: key, value: value)
    }
  }

  deinit {
    if ownsFields {
      cgrpc_metadata_array_unref_fields(underlyingArray)
    }
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
  
  public func add(key: String, value: String) throws {
    if !ownsFields {
      throw Error.doesNotOwnFields
    }
    cgrpc_metadata_array_append_metadata(underlyingArray, key, value)
  }
  
  public var dictionaryRepresentation: [String: String] {
    var result: [String: String] = [:]
    var unknownKeyCount = 0
    for i in 0..<count() {
      let key: String
      if let unwrappedKey = self.key(i) {
        key = unwrappedKey
      } else {
        key = "(unknown\(unknownKeyCount))"
        unknownKeyCount += 1
      }
      result[key] = self.value(i) ?? "(unknown)"
    }
    return result
  }
  
  public func copy() -> Metadata {
    return Metadata(underlyingArray: cgrpc_metadata_array_copy(underlyingArray), ownsFields: true)
  }
  
  func getUnderlyingArrayAndTransferFieldOwnership() throws -> UnsafeMutableRawPointer {
    if !ownsFields {
      throw Error.doesNotOwnFields
    }
    ownsFields = false
    return underlyingArray
  }
}

extension Metadata {
  public subscript(_ key: String) -> String? {
    for i in 0..<self.count() {
      let currentKey = self.key(i)
      guard currentKey == key
        else { continue }
      
      return self.value(i)
    }
    
    return nil
  }
}
