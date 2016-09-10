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

/// A description of a protocol buffer message
public class MessageDescriptor {
  var name: String = ""
  var fieldDescriptors: [FieldDescriptor] = []

  init(message:Message) { // the message should be a DescriptorProto (descriptor.proto)
    if let field = message.oneField("name") {
      name = field.string()
    }
    message.forEachField("field") {(field) in
      let fieldDescriptor = FieldDescriptor(message:field.message())
      fieldDescriptors.append(fieldDescriptor)
    }
  }

  init(description:[String:Any]) {
    let name = (description["name"] as? String)!
    self.name = name
    let fieldDescriptions = description["fields"] as! [[String:Any]]
    for fieldDescription in fieldDescriptions {
      var typeName = ""
      if fieldDescription["type_name"] != nil {
        typeName = fieldDescription["type_name"] as! String
      }
      let parts = typeName.components(separatedBy: ".")
      typeName = parts.last!
      self.fieldDescriptors.append(FieldDescriptor(type: fieldDescription["type"] as! Int,
                                                   name: fieldDescription["name"] as! String,
                                                   tag: fieldDescription["number"] as! Int,
                                                   type_name: typeName,
                                                   label: fieldDescription["label"] as! Int
      ))
    }
  }

  /// lookup the field descriptor for a specified tag
  func fieldDescriptor(tag: Int) -> FieldDescriptor? {
    for fieldDescriptor in fieldDescriptors {
      if (fieldDescriptor.tag == tag) {
        return fieldDescriptor
      }
    }
    print("UNRECOGNIZED \(name):\(tag)")
    return nil
  }
}
