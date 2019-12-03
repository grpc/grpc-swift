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

public struct GRPCStatusMessageMarshaller {
  /// Adds percent encoding to the given message.
  ///
  /// - Parameter message: Message to percent encode.
  /// - Returns: Percent encoded string, or `nil` if it could not be encoded.
  public static func marshall(_ message: String) -> String? {
    return percentEncode(message)
  }

  /// Removes percent encoding from the given message.
  ///
  /// - Parameter message: Message to remove encoding from.
  /// - Returns: The string with percent encoding removed, or the input string if the encoding
  ///   could not be removed.
  public static func unmarshall(_ message: String) -> String {
    return removePercentEncoding(message)
  }
}

extension GRPCStatusMessageMarshaller {
  /// Adds percent encoding to the given message.
  ///
  /// gRPC uses percent encoding as defined in RFC 3986 § 2.1 but with a different set of restricted
  /// characters. The allowed characters are all visible printing characters except for (`%`,
  /// `0x25`). That is: `0x20`-`0x24`, `0x26`-`0x7E`.
  ///
  /// - Parameter message: The message to encode.
  /// - Returns: Percent encoded string, or `nil` if it could not be encoded.
  private static func percentEncode(_ message: String) -> String? {
    let utf8 = message.utf8

    let encodedLength = percentEncodedLength(for: utf8)
    // Fast-path: all characters are valid, nothing to encode.
    if encodedLength == utf8.count {
      return message
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(encodedLength)

    for char in message.utf8 {
      switch char {
      // See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
      case 0x20...0x24,
           0x26...0x7e:
        bytes.append(char)

      default:
        bytes.append(UInt8(ascii: "%"))
        bytes.append(toHex(char >> 4))
        bytes.append(toHex(char & 0xf))
      }
    }

    return String(bytes: bytes, encoding: .utf8)
  }

  /// Returns the percent encoded length of the given `UTF8View`.
  private static func percentEncodedLength(for view: String.UTF8View) -> Int {
    var count = view.count
    for byte in view {
      switch byte {
      case 0x20...0x24,
           0x26...0x7e:
        ()

      default:
        count += 2
      }
    }
    return count
  }

  /// Encode the given byte as hexadecimal.
  ///
  /// - Precondition: Only the four least significant bits may be set.
  /// - Parameter nibble: The nibble to convert to hexadecimal.
  private static func toHex(_ nibble: UInt8) -> UInt8 {
    assert(nibble & 0xf == nibble)

    switch nibble {
    case 0...9:
      return nibble &+ UInt8(ascii: "0")
    default:
      return nibble &+ (UInt8(ascii: "A") &- 10)
    }
  }

  /// Remove gRPC percent encoding from `message`. If any portion of the string could not be decoded
  /// then the encoded message will be returned.
  ///
  /// - Parameter message: The message to remove percent encoding from.
  /// - Returns: The decoded message.
  private static func removePercentEncoding(_ message: String) -> String {
    let utf8 = message.utf8

    let decodedLength = percentDecodedLength(for: utf8)
    // Fast-path: no decoding to do! Note that we may also have detected that the encoding is
    // invalid, in which case we will return the encoded message: this is fine.
    if decodedLength == utf8.count {
      return message
    }

    var chars: [UInt8] = []
    // We can't decode more characters than are already encoded.
    chars.reserveCapacity(decodedLength)

    var currentIndex = utf8.startIndex
    let endIndex = utf8.endIndex

    while currentIndex < endIndex {
      let byte = utf8[currentIndex]

      switch byte {
      case UInt8(ascii: "%"):
        guard let (nextIndex, nextNextIndex) = utf8.nextTwoIndices(after: currentIndex),
          let nextHex = fromHex(utf8[nextIndex]),
          let nextNextHex = fromHex(utf8[nextNextIndex])
          else {
            // If we can't decode the message, aborting and returning the encoded message is fine
            // according to the spec.
            return message
        }
        chars.append((nextHex << 4) | nextNextHex)
        currentIndex = nextNextIndex

      default:
        chars.append(byte)
      }

      currentIndex = utf8.index(after: currentIndex)
    }

    return String(decoding: chars, as: Unicode.UTF8.self)
  }

  /// Returns the expected length of the decoded `UTF8View`.
  private static func percentDecodedLength(for view: String.UTF8View) -> Int {
    var encoded = 0

    for byte in view {
      switch byte {
      case UInt8(ascii: "%"):
        // This can't overflow since it can't be larger than view.count.
        encoded &+= 1

      default:
        ()
      }
    }

    let notEncoded = view.count - (encoded * 3)

    guard notEncoded >= 0 else {
      // We've received gibberish: more '%' than expected. gRPC allows for the status message to
      // be left encoded should it be incorrectly encoded. We'll do exactly that by returning
      // the number of bytes in the view which will causes us to take the fast-path exit.
      return view.count
    }

    return notEncoded + encoded
  }

  private static func fromHex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      return byte &- UInt8(ascii: "0")
    case UInt8(ascii: "A")...UInt8(ascii: "Z"):
      return byte &- (UInt8(ascii: "A") &- 10)
    case UInt8(ascii: "a")...UInt8(ascii: "z"):
      return byte &- (UInt8(ascii: "a") &- 10)
    default:
      return nil
    }
  }
}

extension String.UTF8View {
  /// Return the next two valid indices after the given index. The indices are considered valid if
  /// they less than `endIndex`.
  fileprivate func nextTwoIndices(after index: Index) -> (Index, Index)? {
    let secondIndex = self.index(index, offsetBy: 2)
    guard secondIndex < self.endIndex else {
      return nil
    }

    return (self.index(after: index), secondIndex)
  }
}
