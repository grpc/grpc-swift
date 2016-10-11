/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation // for String.Encoding

/// An item of metadata
private struct MetadataPair {
  var key: String
  var value: String
  init(key:String, value:String) {
    self.key = key
    self.value = value
  }
}

/// Metadata sent with gRPC messages
public class Metadata {

  /// Pointer to underlying C representation
  var underlyingArray: UnsafeMutableRawPointer

  init(underlyingArray: UnsafeMutableRawPointer) {
    self.underlyingArray = underlyingArray
  }

  public init() {
    self.underlyingArray = cgrpc_metadata_array_create();
  }

  public init(_ pairs: [[String:String]]) {
    underlyingArray = cgrpc_metadata_array_create();
    for pair in pairs {
      for key in pair.keys {
        if let value = pair[key] {
          add(key:key, value:value)
        }
      }
    }
  }

  public init(_ pairs: [String:String]) {
    underlyingArray = cgrpc_metadata_array_create();
    for key in pairs.keys {
      if let value = pairs[key] {
        add(key:key, value:value)
      }
    }
  }

  deinit {
    cgrpc_metadata_array_destroy(underlyingArray);
  }

  public func count() -> Int {
    return cgrpc_metadata_array_get_count(underlyingArray);
  }

  public func key(index: Int) -> (String) {
    return String(cString:cgrpc_metadata_array_get_key_at_index(underlyingArray, index),
                  encoding:String.Encoding.utf8)!;
  }

  public func value(index: Int) -> (String) {
    return String(cString:cgrpc_metadata_array_get_value_at_index(underlyingArray, index),
                  encoding:String.Encoding.utf8)!;
  }

  public func add(key:String, value:String) {
    cgrpc_metadata_array_append_metadata(underlyingArray, key, value)
  }
}
