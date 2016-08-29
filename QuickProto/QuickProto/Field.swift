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

/// A representation of a protocol buffer field that can be used to read and build protobufs
public class Field {
  private var descriptor: FieldDescriptor
  private var value: Any!

  init(descriptor: FieldDescriptor, value: Any) {
    self.descriptor = descriptor
    self.value = value
  }

  init(descriptor: FieldDescriptor) {
    self.descriptor = descriptor
  }

  /// display a field for testing and debugging
  func display(indent: String) {
    let type = self.descriptor.type

    var line = indent
    line += String(describing:self.descriptor.label) + " "
    line += String(describing:type)
    if ((type == FieldType.MESSAGE) || (type == FieldType.ENUM)) {
      line += ":" + self.descriptor.type_name
    }
    line += " "
    line += self.descriptor.name
    line += " = "

    if let value = value as? Int {
      line += "\(value)"
      print(line)
    } else if let value = value as? Int32 {
      line += "\(value)"
      print(line)
    } else if let value = value as? Int64 {
      line += "\(value)"
      print(line)
    } else if let value = value as? Bool {
      line += "\(value)"
      print(line)
    } else if let value = value as? String {
      line += "\(value)"
      print(line)
    } else if let message = value as? Message {
      line += " {"
      print(line)
      for field in message.fields {
        field.display(indent:indent + "  ")
      }
      print("\(indent)}")
    } else if let value = value as? Double {
      line += "\(value)"
      print(line)
    } else if let value = value as? Float {
      line += "\(value)"
      print(line)
    } else if let value = value as? NSData {
      line += "\(value)"
      print(line)
    } else {
      line += "???"
      print(line)
    }
  }

  public func name() -> String {
    return descriptor.name
  }

  public func tag() -> Int {
    return descriptor.tag
  }

  public func wireType() -> WireType {
    return descriptor.wireType()
  }

  public func type() -> FieldType {
    return descriptor.type
  }

  public func message() -> Message {
    return value as! Message
  }

  public func data() -> NSData {
    return value as! NSData
  }

  public func string() -> String {
    return value as! String
  }

  public func integer() -> Int {
    return value as! Int
  }

  public func bool() -> Bool {
    return value as! Bool
  }
  
  public func double() -> Double {
    return value as! Double
  }

  public func float() -> Float {
    return value as! Float
  }

  public func setString(_ value:String) {
    self.value = value
  }

  public func setMessage(_ value:Message) {
    self.value = value
  }

  public func setData(_ value:NSData) {
    self.value = value
  }

  public func setInt(_ value:Int) {
    self.value = value
  }

  public func setDouble(_ value:Double) {
    self.value = value
  }

  public func setFloat(_ value:Float) {
    self.value = value
  }

  public func setBool(_ value:Bool) {
    self.value = value
  }

}
