/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension UInt8 {
  @inlinable
  var isASCII: Bool {
    return self <= 127
  }
}

extension String.UTF8View {
  /// Compares two UTF8 strings as case insensitive ASCII bytes.
  ///
  /// - Parameter bytes: The string constant in the form of a collection of `UInt8`
  /// - Returns: Whether the collection contains **EXACTLY** this array or no, but by ignoring case.
  @inlinable
  func compareCaseInsensitiveASCIIBytes(to other: String.UTF8View) -> Bool {
    // fast path: we can get the underlying bytes of both
    let maybeMaybeResult = self.withContiguousStorageIfAvailable { lhsBuffer -> Bool? in
      other.withContiguousStorageIfAvailable { rhsBuffer in
        if lhsBuffer.count != rhsBuffer.count {
          return false
        }

        for idx in 0 ..< lhsBuffer.count {
          // let's hope this gets vectorised ;)
          if lhsBuffer[idx] & 0xdf != rhsBuffer[idx] & 0xdf && lhsBuffer[idx].isASCII {
            return false
          }
        }
        return true
      }
    }

    if let maybeResult = maybeMaybeResult, let result = maybeResult {
      return result
    } else {
      return self._compareCaseInsensitiveASCIIBytesSlowPath(to: other)
    }
  }

  @inlinable
  @inline(never)
  func _compareCaseInsensitiveASCIIBytesSlowPath(to other: String.UTF8View) -> Bool {
    return self.elementsEqual(other, by: { return (($0 & 0xdf) == ($1 & 0xdf) && $0.isASCII) })
  }
}

extension String {
  @inlinable
  func isEqualCaseInsensitiveASCIIBytes(to: String) -> Bool {
    return self.utf8.compareCaseInsensitiveASCIIBytes(to: to.utf8)
  }
}
