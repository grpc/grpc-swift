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

/// Representation of the file to be created by the code generator, that contains the
/// generated Swift source code.
public struct SourceFile: Sendable {
  /// The base name of the file.
  public var name: String

  /// The generated code encoded as UTF-8 data.
  public var sourceCode: Data

  /// Creates a representation of a file containing Swift code with the specified name
  /// and  contents.
  public init(name: String, sourceCode: Data) {
    self.name = name
    self.sourceCode = sourceCode
  }
}
