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

/// A non-empty list which is guaranteed to have a first and last element.
///
/// This is required since we want to directly store the first and last elements: in some cases
/// `Array.first` and `Array.last` will allocate: unfortunately this currently happens to be the
/// case for the interceptor pipelines. Storing the `first` and `last` directly allows us to avoid
/// this. See also: https://bugs.swift.org/browse/SR-11262.
@usableFromInline
internal struct InterceptorContextList<Element> {
  /// The first element, stored at `middle.startIndex - 1`.
  @usableFromInline
  internal var first: Element

  /// The last element, stored at the `middle.endIndex`.
  @usableFromInline
  internal var last: Element

  /// The other elements.
  @usableFromInline
  internal var _middle: [Element]

  /// The index of `first`
  @usableFromInline
  internal let firstIndex: Int

  /// The index of `last`.
  @usableFromInline
  internal let lastIndex: Int

  @usableFromInline
  internal subscript(checked index: Int) -> Element? {
    switch index {
    case self.firstIndex:
      return self.first
    case self.lastIndex:
      return self.last
    default:
      return self._middle[checked: index]
    }
  }

  @inlinable
  internal init(first: Element, middle: [Element], last: Element) {
    self.first = first
    self._middle = middle
    self.last = last
    self.firstIndex = middle.startIndex - 1
    self.lastIndex = middle.endIndex
  }
}
