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

#if os(Linux)
@preconcurrency import struct Foundation.URL
@preconcurrency import struct Foundation.Data
#else
import struct Foundation.URL
import struct Foundation.Data
#endif

/// An in-memory input file that contains the raw data of an OpenAPI document.
///
/// Contents are formatted as either YAML or JSON.
public struct InMemoryInputFile: Sendable {

  /// The absolute path to the file.
  public var absolutePath: URL

  /// The YAML or JSON file contents encoded as UTF-8 data.
  public var contents: Data

  /// Creates a file with the specified path and contents.
  /// - Parameters:
  ///   - absolutePath: An absolute path to the file.
  ///   - contents: Data contents of the file, encoded as UTF-8.
  public init(absolutePath: URL, contents: Data) {
    self.absolutePath = absolutePath
    self.contents = contents
  }
}
