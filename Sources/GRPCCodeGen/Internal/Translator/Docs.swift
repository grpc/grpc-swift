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

@available(gRPCSwift 2.0, *)
package enum Docs {
  package static func suffix(_ header: String, withDocs footer: String) -> String {
    if footer.isEmpty {
      return header
    } else {
      let docs = """
        ///
        \(Self.inlineDocsAsNote(footer))
        """
      return header + "\n" + docs
    }
  }

  package static func interposeDocs(
    _ docs: String,
    between header: String,
    and footer: String
  ) -> String {
    let middle: String

    if docs.isEmpty {
      middle = """
        ///
        """
    } else {
      middle = """
        ///
        \(Self.inlineDocsAsNote(docs))
        ///
        """
    }

    return header + "\n" + middle + "\n" + footer
  }

  private static func inlineDocsAsNote(_ docs: String) -> String {
    let header = """
      /// > Source IDL Documentation:
      /// >
      """

    let body = docs.split(separator: "\n").map { line in
      var line = "/// > " + line.dropFirst(4)
      line.trimPrefix(while: { $0.isWhitespace })
      return String(line.drop(while: { $0.isWhitespace }))
    }.joined(separator: "\n")

    return header + "\n" + body
  }
}
