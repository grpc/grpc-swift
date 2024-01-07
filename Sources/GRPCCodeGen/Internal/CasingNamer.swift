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
// Sources/SwiftProtobufPluginLibrary/NamingUtils.swift - Utilities for generating names
//
// Copyright (c) 2014 - 2017 Apple Inc. and the project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information:
// https://github.com/apple/swift-protobuf/blob/main/LICENSE.txt
//

import Foundation

private enum CamelCaser {
  // Abbreviations for which all characters should be either uppercase or lowercase
  // when camel casing.
  static let abbreviations: Set<String> = ["url", "http", "https", "id"]

  // The different "classes" a character can belong to for segmenting.
  enum CharClass {
    case digit
    case lower
    case upper
    case underscore
    case other

    init(_ from: UnicodeScalar) {
      switch from {
      case "0" ... "9":
        self = .digit
      case "a" ... "z":
        self = .lower
      case "A" ... "Z":
        self = .upper
      case "_":
        self = .underscore
      default:
        self = .other
      }
    }
  }

  /// Transforms the input into a camelcase name that is a valid Swift
  /// identifier. The input can be either a "snake_case_name" or a camelcase name
  /// for which we need to change the first character(s) casing.
  /// The splits happen based on underscores and/or changes in case
  /// and/or use of digits. If underscores are repeated, then the "extras"
  /// (past the first) are carried over into the output.
  ///
  /// NOTE: Since leading underscores are removed, it does
  /// have to handle leading digits. If this is the case,
  /// then an underscore is added before it.
  static func transform(_ s: String, leadingCharacterUpperCase: Bool) -> String {
    var result = String()
    var current = String.UnicodeScalarView()
    var lastClass = CharClass("\0")

    func addCurrent() {
      guard !current.isEmpty else {
        return
      }
      var currentAsString = String(current)
      if result.isEmpty && !leadingCharacterUpperCase {
        // Nothing, we want it to stay lowercase.
      } else if abbreviations.contains(currentAsString) {
        currentAsString = currentAsString.uppercased()
      } else {
        currentAsString = CasingNamer.uppercaseFirstCharacter(currentAsString)
      }
      result += String(currentAsString)
      current = String.UnicodeScalarView()
    }

    for scalar in s.unicodeScalars {
      let scalarClass = CharClass(scalar)
      switch scalarClass {
      case .digit:
        if lastClass != .digit {
          addCurrent()
        }
        if result.isEmpty {
          // We don't want a number as the first character.
          result += "_"
        }
        current.append(scalar)
      case .upper:
        if lastClass != .upper {
          addCurrent()
        }
        current.append(scalar.ascLowercased())
      case .lower:
        if lastClass != .lower && lastClass != .upper {
          addCurrent()
        }
        current.append(scalar)
      case .underscore:
        addCurrent()
        if lastClass == .underscore {
          result += "_"
        }
      case .other:
        addCurrent()
        let escapeIt =
          result.isEmpty
          ? !isSwiftIdentifierHeadCharacter(scalar)
          : !isSwiftIdentifierCharacter(scalar)
        if escapeIt {
          result.append("_u\(scalar.value)")
        } else {
          current.append(scalar)
        }
      }

      lastClass = scalarClass
    }

    // Add the last segment collected.
    addCurrent()

    // If things end in an underscore, add one also.
    if lastClass == .underscore {
      result += "_"
    }

    return result
  }
}

private func makeUnicodeScalarView(
  from unicodeScalar: UnicodeScalar
) -> String.UnicodeScalarView {
  var view = String.UnicodeScalarView()
  view.append(unicodeScalar)
  return view
}

public enum CasingNamer {
  /// Forces the first character to be uppercase (if possible) and leaves
  /// the rest of the characters in their existing case.
  ///
  /// Use toUpperCamelCase() to get leading "HTTP", "URL", etc. correct.
  static func uppercaseFirstCharacter(_ s: String) -> String {
    let out = s.unicodeScalars
    if let first = out.first {
      var result = makeUnicodeScalarView(from: first.ascUppercased())
      result.append(
        contentsOf: out[out.index(after: out.startIndex) ..< out.endIndex]
      )
      return String(result)
    } else {
      return s
    }
  }

  /// Accepts any inputs and transforms form it into a leading
  /// UpperCaseCamelCased Swift identifier.
  public static func toUpperCamelCase(_ s: String) -> String {
    return CamelCaser.transform(s, leadingCharacterUpperCase: true)
  }

  /// Accepts any inputs and transforms form it into a leading
  /// lowerCaseCamelCased Swift identifier.
  public static func toLowerCamelCase(_ s: String) -> String {
    return CamelCaser.transform(s, leadingCharacterUpperCase: false)
  }
}

extension UnicodeScalar {
  /// True if the receiver is a lowercase character.
  var isASCLowercase: Bool {
    if case "a" ... "z" = self { return true }
    return false
  }

  /// True if the receiver is an uppercase character.
  var isASCUppercase: Bool {
    if case "A" ... "Z" = self { return true }
    return false
  }

  /// Returns the lowercased version of the receiver, or the receiver itself if
  /// it is not a cased character.
  ///
  /// - Precondition: The receiver is 7-bit ASCII.
  /// - Returns: The lowercased version of the receiver, or `self`.
  func ascLowercased() -> UnicodeScalar {
    if isASCUppercase { return UnicodeScalar(value + 0x20)! }
    return self
  }

  /// Returns the uppercased version of the receiver, or the receiver itself if
  /// it is not a cased character.
  ///
  /// - Precondition: The receiver is 7-bit ASCII.
  /// - Returns: The uppercased version of the receiver, or `self`.
  func ascUppercased() -> UnicodeScalar {
    if isASCLowercase { return UnicodeScalar(value - 0x20)! }
    return self
  }
}

/// Used to check if a character is a valid identifier head character.
func isSwiftIdentifierHeadCharacter(_ c: UnicodeScalar) -> Bool {
  switch c.value {
  // identifier-head → Upper- or lowercase letter A through Z
  case 0x61 ... 0x7a, 0x41 ... 0x5a: return true
  // identifier-head → _
  case 0x5f: return true
  // identifier-head → U+00A8, U+00AA, U+00AD, U+00AF, U+00B2–U+00B5, or U+00B7–U+00BA
  case 0xa8, 0xaa, 0xad, 0xaf, 0xb2 ... 0xb5, 0xb7 ... 0xba: return true
  // identifier-head → U+00BC–U+00BE, U+00C0–U+00D6, U+00D8–U+00F6, or U+00F8–U+00FF
  case 0xbc ... 0xbe, 0xc0 ... 0xd6, 0xd8 ... 0xf6, 0xf8 ... 0xff: return true
  // identifier-head → U+0100–U+02FF, U+0370–U+167F, U+1681–U+180D, or U+180F–U+1DBF
  case 0x100 ... 0x2ff, 0x370 ... 0x167f, 0x1681 ... 0x180d, 0x180f ... 0x1dbf: return true
  // identifier-head → U+1E00–U+1FFF
  case 0x1e00 ... 0x1fff: return true
  // identifier-head → U+200B–U+200D, U+202A–U+202E, U+203F–U+2040, U+2054, or U+2060–U+206F
  case 0x200b ... 0x200d, 0x202a ... 0x202e, 0x203F, 0x2040, 0x2054, 0x2060 ... 0x206f: return true
  // identifier-head → U+2070–U+20CF, U+2100–U+218F, U+2460–U+24FF, or U+2776–U+2793
  case 0x2070 ... 0x20cf, 0x2100 ... 0x218f, 0x2460 ... 0x24ff, 0x2776 ... 0x2793: return true
  // identifier-head → U+2C00–U+2DFF or U+2E80–U+2FFF
  case 0x2c00 ... 0x2dff, 0x2e80 ... 0x2fff: return true
  // identifier-head → U+3004–U+3007, U+3021–U+302F, U+3031–U+303F, or U+3040–U+D7FF
  case 0x3004 ... 0x3007, 0x3021 ... 0x302f, 0x3031 ... 0x303f, 0x3040 ... 0xd7ff: return true
  // identifier-head → U+F900–U+FD3D, U+FD40–U+FDCF, U+FDF0–U+FE1F, or U+FE30–U+FE44
  case 0xf900 ... 0xfd3d, 0xfd40 ... 0xfdcf, 0xfdf0 ... 0xfe1f, 0xfe30 ... 0xfe44: return true
  // identifier-head → U+FE47–U+FFFD
  case 0xfe47 ... 0xfffd: return true
  // identifier-head → U+10000–U+1FFFD, U+20000–U+2FFFD, U+30000–U+3FFFD, or U+40000–U+4FFFD
  case 0x10000 ... 0x1fffd, 0x20000 ... 0x2fffd, 0x30000 ... 0x3fffd, 0x40000 ... 0x4fffd:
    return true
  // identifier-head → U+50000–U+5FFFD, U+60000–U+6FFFD, U+70000–U+7FFFD, or U+80000–U+8FFFD
  case 0x50000 ... 0x5fffd, 0x60000 ... 0x6fffd, 0x70000 ... 0x7fffd, 0x80000 ... 0x8fffd:
    return true
  // identifier-head → U+90000–U+9FFFD, U+A0000–U+AFFFD, U+B0000–U+BFFFD, or U+C0000–U+CFFFD
  case 0x90000 ... 0x9fffd, 0xa0000 ... 0xafffd, 0xb0000 ... 0xbfffd, 0xc0000 ... 0xcfffd:
    return true
  // identifier-head → U+D0000–U+DFFFD or U+E0000–U+EFFFD
  case 0xd0000 ... 0xdfffd, 0xe0000 ... 0xefffd: return true

  default: return false
  }
}

/// Used to check if a character is a valid identifier character.
func isSwiftIdentifierCharacter(_ c: UnicodeScalar) -> Bool {
  switch c.value {
  // identifier-character → Digit 0 through 9
  case 0x30 ... 0x39: return true
  // identifier-character → U+0300–U+036F, U+1DC0–U+1DFF, U+20D0–U+20FF, or U+FE20–U+FE2F
  case 0x300 ... 0x36F, 0x1dc0 ... 0x1dff, 0x20d0 ... 0x20ff, 0xfe20 ... 0xfe2f: return true
  // identifier-character → identifier-head
  default: return isSwiftIdentifierHeadCharacter(c)
  }
}
