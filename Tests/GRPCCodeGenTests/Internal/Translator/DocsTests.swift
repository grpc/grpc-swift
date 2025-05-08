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

import GRPCCodeGen
import Testing

@Suite("Docs tests")
struct DocsTests {
  @Test("Suffix with additional docs")
  @available(gRPCSwift 2.0, *)
  func suffixWithAdditional() {
    let foo = """
      /// Foo
      """

    let additional = """
      /// Some additional pre-formatted docs
      /// split over multiple lines.
      """

    let expected = """
      /// Foo
      ///
      /// > Source IDL Documentation:
      /// >
      /// > Some additional pre-formatted docs
      /// > split over multiple lines.
      """
    #expect(Docs.suffix(foo, withDocs: additional) == expected)
  }

  @Test("Suffix with empty additional docs")
  @available(gRPCSwift 2.0, *)
  func suffixWithEmptyAdditional() {
    let foo = """
      /// Foo
      """

    let additional = ""
    #expect(Docs.suffix(foo, withDocs: additional) == foo)
  }

  @Test("Interpose additional docs")
  @available(gRPCSwift 2.0, *)
  func interposeDocs() {
    let header = """
      /// Header
      """

    let footer = """
      /// Footer
      """

    let additionalDocs = """
      /// Additional docs
      /// On multiple lines
      """

    let expected = """
      /// Header
      ///
      /// > Source IDL Documentation:
      /// >
      /// > Additional docs
      /// > On multiple lines
      ///
      /// Footer
      """

    #expect(Docs.interposeDocs(additionalDocs, between: header, and: footer) == expected)
  }

  @Test("Interpose empty additional docs")
  @available(gRPCSwift 2.0, *)
  func interposeEmpty() {
    let header = """
      /// Header
      """

    let footer = """
      /// Footer
      """

    let expected = """
      /// Header
      ///
      /// Footer
      """

    #expect(Docs.interposeDocs("", between: header, and: footer) == expected)
  }
}
