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

/// An object that renders structured Swift representations
/// into Swift files.
///
/// Rendering is the last phase of the generator pipeline.
protocol RendererProtocol {

  /// Renders the specified structured code into a raw Swift file.
  /// - Parameters:
  ///   - code: A structured representation of the Swift code.
  ///   - config: The configuration of the generator.
  ///   - diagnostics: The collector to which to emit diagnostics.
  /// - Returns: A raw file with Swift contents.
  /// - Throws: An error if an issue occurs during rendering.
  func render(structured code: StructuredSwiftRepresentation) throws -> SourceFile
}
