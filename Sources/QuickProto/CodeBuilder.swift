/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
import Foundation

/// A code generator that builds a structure describing the contents of the FileDescriptorSet proto
public class CodeBuilder {

  private var code : String = ""

  public func string() -> String {
    return code
  }

  /// the initializer builds a code representation from a message
  public init(_ message: Message) {
    code = ""
    code += "import Foundation\n"
    code += "\n"
    code += "var _FileDescriptor : [[String:Any]] = [\n"
    message.forEachField(["file","message_type"]) {(field) in
      generateProtoDescription(field:field)
    }
    code += "];\n"
  }

  /// generate code for a dictionary literal describing a proto
  private func generateProtoDescription(field: Field) {
    field.message().forEachField("name") {(field) in
      code += "  [\"name\": \"\(field.string())\",\n"
      code += "   \"fields\": [\n"
    }
    field.message().forEachField("field") {(field) in
      var name : String?
      var number : Int?
      var type : Int = 0
      var label : Int = 0
      var typeName : String? = ""
      for field in field.message().fields {
        if field.name() == "name" {
          name = field.string()
        } else if field.name() == "number" {
          number = field.integer()
        } else if field.name() == "type_name" {
          typeName = field.string()
        } else if field.name() == "type" {
          type = field.integer()
        } else if field.name() == "label" {
          label = field.integer()
        }
      }
      if let name = name,
        let number = number,
        let typeName = typeName {
        code +=  "    [\"number\":\(number), \"name\":\"\(name)\", \"label\":\(label), \"type\":\(type), \"type_name\":\"\(typeName)\"],\n"
      }
    }
    code += "    ]],\n"
    field.message().forEachField("nested_type") {(field) in
      generateProtoDescription(field:field)
    }
  }
}
