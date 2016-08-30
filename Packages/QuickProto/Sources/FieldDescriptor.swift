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

/// A description of a field in a protocol buffer message
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

  func wireType() -> WireType {
    switch type {
    case FieldType.DOUBLE   : return WireType.FIXED64
    case FieldType.FLOAT    : return WireType.FIXED32
    case FieldType.INT64    : return WireType.VARINT
    case FieldType.UINT64   : return WireType.VARINT
    case FieldType.INT32    : return WireType.VARINT
    case FieldType.FIXED64  : return WireType.FIXED64
    case FieldType.FIXED32  : return WireType.FIXED32
    case FieldType.BOOL     : return WireType.VARINT
    case FieldType.STRING   : return WireType.LENGTH_DELIMITED
    case FieldType.GROUP    : return WireType.START_GROUP
    case FieldType.MESSAGE  : return WireType.LENGTH_DELIMITED
    case FieldType.BYTES    : return WireType.LENGTH_DELIMITED
    case FieldType.UINT32   : return WireType.VARINT
    case FieldType.ENUM     : return WireType.VARINT
    case FieldType.SFIXED32 : return WireType.FIXED32
    case FieldType.SFIXED64 : return WireType.FIXED64
    case FieldType.SINT32   : return WireType.VARINT
    case FieldType.SINT64   : return WireType.VARINT
    }
  }
}
