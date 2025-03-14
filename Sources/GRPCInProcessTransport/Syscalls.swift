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
private import Darwin
#elseif canImport(Android)
private import Android  // should be @usableFromInline
#elseif canImport(Glibc)
private import Glibc  // should be @usableFromInline
#elseif canImport(Musl)
private import Musl  // should be @usableFromInline
#else
#error("Unsupported OS")
#endif

enum System {
  static func pid() -> Int {
    #if canImport(Darwin)
    let pid = Darwin.getpid()
    return Int(pid)
    #elseif canImport(Android)
    let pid = Android.getpid()
    return Int(pid)
    #elseif canImport(Glibc)
    let pid = Glibc.getpid()
    return Int(pid)
    #elseif canImport(Musl)
    let pid = Musl.getpid()
    return Int(pid)
    #endif
  }
}
