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
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Foundation

/// A fully-qualified type name that contains the components of the Swift
/// type name.
///
/// Use the type name to define a type, see also `TypeUsage` when referring
/// to a type.
struct TypeName: Hashable {
  /// A list of components that make up the type name.
  private let components: [String]

  /// Creates a new type name with the specified list of components.
  /// - Parameter components: A list of components for the type.
  init(components: [String]) {
    precondition(!components.isEmpty, "TypeName path cannot be empty")
    self.components = components
  }

  /// A string representation of the fully qualified Swift type name.
  ///
  /// For example: `Swift.Int`.
  var fullyQualifiedName: String { components.joined(separator: ".") }

  /// A string representation of the last path component of the Swift
  /// type name.
  ///
  /// For example: `Int`.
  var shortName: String { components.last! }

  /// Returns a type name by appending the specified component to the
  /// current type name.
  ///
  /// In other words, returns a type name for a child type.
  /// - Parameters:
  ///   - component: The name of the Swift type component.
  /// - Returns: A new type name.
  func appending(component: String) -> Self {
    return .init(components: components + [component])
  }

  /// Returns a type name by removing the last component from the current
  /// type name.
  ///
  /// In other words, returns a type name for the parent type.
  var parent: TypeName {
    precondition(components.count >= 1, "Cannot get the parent of a root type")
    return .init(components: components.dropLast())
  }
}

extension TypeName: CustomStringConvertible {
  var description: String {
    return fullyQualifiedSwiftName
  }
}

extension TypeName {
  /// Returns the type name for the String type.
  static var string: Self { .swift("String") }

  /// Returns the type name for the Int type.
  static var int: Self { .swift("Int") }

  /// Returns a type name for a type with the specified name in the
  /// Swift module.
  /// - Parameter name: The name of the type.
  /// - Returns: A TypeName representing the specified type within the Swift module.
  static func swift(_ name: String) -> TypeName { TypeName(components: ["Swift", name]) }

  /// Returns a type name for a type with the specified name in the
  /// Foundation module.
  /// - Parameter name: The name of the type.
  /// - Returns: A TypeName representing the specified type within the Foundation module.
  static func foundation(_ name: String) -> TypeName {
    TypeName(components: ["Foundation", name])
  }
}
