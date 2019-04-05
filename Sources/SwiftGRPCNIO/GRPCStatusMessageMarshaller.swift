/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation

public struct GRPCStatusMessageMarshaller {
  // See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  // 0x20-0x24 and 0x26-0x7e inclusive.
  public static let allowedCharacters: CharacterSet = {
    var allowed = CharacterSet(charactersIn: Unicode.Scalar(0x20)...Unicode.Scalar(0x7e))
    // Remove '%' (0x25)
    allowed.remove(Unicode.Scalar(0x25))
    return allowed
  }()

  /// Adds percent encoding to the given message.
  ///
  /// - Parameter message: Message to percent encode.
  /// - Returns: Percent encoded string, or `nil` if it could not be encoded.
  public static func marshall(_ message: String) -> String? {
    return message.addingPercentEncoding(withAllowedCharacters: GRPCStatusMessageMarshaller.allowedCharacters)
  }

  /// Removes percent encoding from the given message.
  ///
  /// - Parameter message: Message to remove encoding from.
  /// - Returns: The string with percent encoding removed, or the input string if the encoding
  ///   could not be removed.
  public static func unmarshall(_ message: String) -> String {
    return message.removingPercentEncoding ?? message
  }
}
