/*
 * Copyright 2021, gRPC Authors All rights reserved.
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

@usableFromInline
internal struct ConnectionManagerID: Hashable, CustomStringConvertible, GRPCSendable {
  @usableFromInline
  internal let _id: ObjectIdentifier

  @usableFromInline
  internal init(_ manager: ConnectionManager) {
    self._id = ObjectIdentifier(manager)
  }

  @usableFromInline
  internal var description: String {
    return String(describing: self._id)
  }
}

extension ConnectionManager {
  @usableFromInline
  internal var id: ConnectionManagerID {
    return ConnectionManagerID(self)
  }
}
