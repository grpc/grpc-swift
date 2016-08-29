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

// Describes a field in a message
public class FieldDescriptor {
  var type : FieldType
  var label : FieldLabel
  var name : String = ""
  var tag : Int = 0
  var type_name : String = ""

  init(type: Int, name: String, tag: Int, type_name: String, label: Int) {
    self.name = name
    self.type = FieldType(rawValue:type)!
    self.tag = tag
    self.type_name = type_name
    self.label = FieldLabel(rawValue:label)!
  }

  init(message: Message) {
    name = message.oneField(name:"name")!.string()
    type = FieldType(rawValue:message.oneField(name:"type")!.integer())!
    tag = message.oneField(name:"number")!.integer()
    if let field = message.oneField(name:"type_name") {
      type_name = field.string()
    }
    label = FieldLabel(rawValue:message.oneField(name:"label")!.integer())!
  }

  func wireType() -> Int {
    switch type {
    case FieldType.DOUBLE   : return 1
    case FieldType.FLOAT    : return 5
    case FieldType.INT64    : return 0
    case FieldType.UINT64   : return 0
    case FieldType.INT32    : return 0
    case FieldType.FIXED64  : return 1
    case FieldType.FIXED32  : return 5
    case FieldType.BOOL     : return 0
    case FieldType.STRING   : return 2
    case FieldType.GROUP    : return 3
    case FieldType.MESSAGE  : return 2
    case FieldType.BYTES    : return 2
    case FieldType.UINT32   : return 0
    case FieldType.ENUM     : return 0
    case FieldType.SFIXED32 : return 5
    case FieldType.SFIXED64 : return 1
    case FieldType.SINT32   : return 0
    case FieldType.SINT64   : return 0
    }
  }
}
