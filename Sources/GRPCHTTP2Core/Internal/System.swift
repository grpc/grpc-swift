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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum System {
  static func hostname() -> String {
    var buffer = [CChar](repeating: 0, count: 256)

    // The return code can only be okay or ENAMETOOLONG. If the name is too long (it shouldn't
    // because the POSIX limit is 255 excluding the null terminator) it will be truncated.
    _ = buffer.withUnsafeMutableBufferPointer { pointer in
      #if canImport(Darwin)
      Darwin.gethostname(pointer.baseAddress, pointer.count)
      #elseif canImport(Glibc)
      Glibc.gethostname(pointer.baseAddress, pointer.count)
      #elseif canImport(Musl)
      Musl.gethostname(pointer.baseAddress, pointer.count)
      #endif
    }

    return String(cString: buffer)
  }
}
