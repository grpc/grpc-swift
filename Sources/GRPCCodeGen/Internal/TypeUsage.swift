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

/// A reference to a Swift type, including modifiers such as whether the
/// type is wrapped in an optional, an array, or a dictionary.
///
/// Whenever unsure whether to use `TypeUsage` or `TypeName` in a new API,
/// consider whether you need to define a type or refer to a type.
///
/// To define a type, use `TypeName`, and to refer to a type, use `TypeUsage`.
///
/// This type is not meant to represent all the various ways types can be
/// wrapped in Swift, only the ways we wrap things in this project. For example,
/// double optionals (`String??`) are automatically collapsed into a single
/// optional, and so on.
struct TypeUsage {

  /// Describes either a type name or a type usage.
  fileprivate indirect enum Wrapped {

    /// A type name, used to define a type.
    case name(TypeName)

    /// A type usage, used to refer to a type.
    case usage(TypeUsage)
  }

  /// The underlying type.
  fileprivate var wrapped: Wrapped

  /// Describes the usage of the wrapped type.
  fileprivate enum Usage {

    /// An unchanged underlying type.
    ///
    /// For example: `Wrapped` stays `Wrapped`.
    case identity

    /// An optional wrapper for the underlying type.
    ///
    /// For example: `Wrapped` becomes `Wrapped?`.
    case optional

    /// An array wrapped for the underlying type.
    ///
    /// For example: `Wrapped` becomes `[Wrapped]`.
    case array

    /// A dictionary value wrapper for the underlying type.
    ///
    /// For example: `Wrapped` becomes `[String: Wrapped]`.
    case dictionaryValue

    /// A generic type wrapper for the underlying type.
    ///
    /// For example, `Wrapped` becomes `Wrapper<Wrapped>`.
    case generic(wrapper: TypeName)
  }

  /// The type usage applied to the underlying type.
  fileprivate var usage: Usage
}

extension TypeUsage: CustomStringConvertible { var description: String { fullyQualifiedName } }

extension TypeUsage {

  /// A Boolean value that indicates whether the type is optional.
  var isOptional: Bool {
    guard case .optional = usage else { return false }
    return true
  }

  /// A string representation of the last component of the Swift type name.
  ///
  /// For example: `Int`.
  var shortName: String {
    let component: String
    switch wrapped {
    case let .name(typeName): component = typeName.shortName
    case let .usage(usage): component = usage.shortName
    }
    return applied(to: component)
  }

  /// A string representation of the fully qualified type name.
  ///
  /// For example: `Swift.Int`.
  var fullyQualifiedName: String {
    let component: String
    switch wrapped {
    case let .name(typeName): component = typeName.fullyQualifiedName
    case let .usage(usage): component = usage.fullyQualifiedName
    }
    return applied(to: component)
  }

  /// A string representation of the fully qualified Swift type name, with
  /// any optional wrapping removed.
  ///
  /// For example: `Swift.Int`.
  var fullyQualifiedNonOptionalName: String { withOptional(false).fullyQualifiedName }

  /// Returns a string representation of the type usage applied to the
  /// specified Swift path component.
  /// - Parameter component: A Swift path component.
  /// - Returns: A string representation of the specified Swift path component with the applied type usage.
  private func applied(to component: String) -> String {
    switch usage {
    case .identity: return component
    case .optional: return component + "?"
    case .array: return "[" + component + "]"
    case .dictionaryValue: return "[String: " + component + "]"
    case .generic(wrapper: let wrapper):
      return "\(wrapper.fullyQualifiedName)<" + component + ">"
    }
  }

  /// The type name wrapped by the current type usage.
  var typeName: TypeName {
    switch wrapped {
    case .name(let typeName): return typeName
    case .usage(let typeUsage): return typeUsage.typeName
    }
  }

  /// A type usage created by treating the current type usage as an optional
  /// type.
  var asOptional: Self {
    // Don't double wrap optionals
    guard !isOptional else { return self }
    return TypeUsage(wrapped: .usage(self), usage: .optional)
  }

  /// A type usage created by removing the outer type usage wrapper.
  private var unwrappedOneLevel: Self {
    switch wrapped {
    case let .usage(usage): return usage
    case let .name(typeName): return typeName.asUsage
    }
  }

  /// Returns a type usage created by adding or removing an optional wrapper,
  /// controlled by the specified parameter.
  /// - Parameter isOptional: If `true`, wraps the current type usage in
  /// an optional. If `false`, removes a potential optional wrapper from the
  /// top level.
  /// - Returns: A type usage with the adjusted optionality based on the `isOptional` parameter.
  func withOptional(_ isOptional: Bool) -> Self {
    if (isOptional && self.isOptional) || (!isOptional && !self.isOptional) { return self }
    guard isOptional else { return unwrappedOneLevel }
    return asOptional
  }

  /// A type usage created by treating the current type usage as the element
  /// type of an array.
  /// - Returns: A type usage for the array.
  var asArray: Self { TypeUsage(wrapped: .usage(self), usage: .array) }

  /// A type usage created by treating the current type usage as the value
  /// type of a dictionary.
  /// - Returns: A type usage for the dictionary.
  var asDictionaryValue: Self { TypeUsage(wrapped: .usage(self), usage: .dictionaryValue) }

  /// A type usage created by wrapping the current type usage inside the
  /// wrapper type, where the wrapper type is generic over the current type.
  func asWrapped(in wrapper: TypeName) -> Self {
    TypeUsage(wrapped: .usage(self), usage: .generic(wrapper: wrapper))
  }
}

extension TypeName {

  /// A type usage that wraps the current type name without changing it.
  var asUsage: TypeUsage { TypeUsage(wrapped: .name(self), usage: .identity) }
}

extension ExistingTypeDescription {

  /// Creates a new type description from the provided type usage's wrapped
  /// value.
  /// - Parameter wrapped: The wrapped value.
  private init(_ wrapped: TypeUsage.Wrapped) {
    switch wrapped {
    case .name(let typeName): self = .init(typeName)
    case .usage(let typeUsage): self = .init(typeUsage)
    }
  }

  /// Creates a new type description from the provided type name.
  /// - Parameter typeName: A type name.
  init(_ typeName: TypeName) { self = .member(typeName.components) }

  /// Creates a new type description from the provided type usage.
  /// - Parameter typeUsage: A type usage.
  init(_ typeUsage: TypeUsage) {
    switch typeUsage.usage {
    case .generic(wrapper: let wrapper):
      self = .generic(wrapper: .init(wrapper), wrapped: .init(typeUsage.wrapped))
    case .optional: self = .optional(.init(typeUsage.wrapped))
    case .identity: self = .init(typeUsage.wrapped)
    case .array: self = .array(.init(typeUsage.wrapped))
    case .dictionaryValue: self = .dictionaryValue(.init(typeUsage.wrapped))
    }
  }
}
