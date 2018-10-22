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

public final class gRPC {
  private init() { }  // Static members only.
  
  /// Initializes gRPC system
  public static func initialize() {
    grpc_init()
  }
  
  /// Shuts down gRPC system
  public static func shutdown() {
    grpc_shutdown()
  }
  
  /// Returns version of underlying gRPC library
  ///
  /// Returns: gRPC version string
  public static var version: String {
    // These two should always be valid UTF-8 strings, so we can forcibly unwrap them.
    return String(cString: grpc_version_string(), encoding: String.Encoding.utf8)!
  }
  
  /// Returns name associated with gRPC version
  ///
  /// Returns: gRPC version name
  public static var gStandsFor: String {
    return String(cString: grpc_g_stands_for(), encoding: String.Encoding.utf8)!
  }
}
