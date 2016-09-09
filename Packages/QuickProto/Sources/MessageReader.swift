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

// A reader for protocol buffers. Used internally.
class MessageReader {
  var fileDescriptorSet: FileDescriptorSet
  var messageName: String
  var data : Data
  var cursor : Int = 0

  init(_ fileDescriptorSet: FileDescriptorSet, messageName: String, data: Data) {
    self.fileDescriptorSet = fileDescriptorSet
    self.messageName = messageName
    self.data = data
  }

  func readMessage() -> Message? {
    if let descriptor = fileDescriptorSet.messageDescriptor(name: messageName) {
      return readMessage(range: NSRange(location: 0, length:data.count),
                         descriptor:descriptor)
    } else {
      return nil
    }
  }

  private func nextUInt8() -> (UInt8) {
    var result: UInt8 = 0
    data.copyBytes(to: &result, from:cursor..<cursor+1)
    cursor += 1
    return result
  }

  private func nextUInt32() -> (UInt32) {
    var result: UInt32 = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+4)
    cursor += 4
    return result
  }

  private func nextUInt64() -> (UInt64) {
    var result: UInt64 = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+8)
    cursor += 8
    return result
  }

  private func nextInt32() -> (Int32) {
    var result: Int32 = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+4)
    cursor += 4
    return result
  }

  private func nextInt64() -> (Int64) {
    var result: Int64 = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+8)
    cursor += 8
    return result
  }

  private func nextDouble() -> (Double) {
    var result: Double = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+8)
    cursor += 8
    return result
  }

  private func nextFloat() -> (Float) {
    var result: Float = 0
    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &result, count: 1), from:cursor..<cursor+4)
    cursor += 4
    return result
  }

  private func nextVarint() -> (Int) {
    var sum : Int = 0
    var shift : Int = 0
    var b : Int = Int(self.nextUInt8())
    while (b & 0x80 != 0) {
      sum += (b & 0x7f) << shift
      shift += 7
      b = Int(self.nextUInt8())
    }
    sum += b << shift
    return sum
  }

  private func nextString(length: Int) -> (String) {
    var buffer = [UInt8](repeating: 0, count: length)
    data.copyBytes(to: &buffer, from:cursor..<cursor+length)
    self.cursor = self.cursor + length
    return String(bytes: buffer, encoding:String.Encoding.utf8)!
  }

  private func nextData(length: Int) -> (Data) {
    var buffer = [UInt8](repeating: 0, count: length)
    data.copyBytes(to: &buffer, from:cursor..<cursor+length)
    self.cursor = self.cursor + length
    return Data(bytes: &buffer, count: length)
  }

  private func readMessage(range: NSRange, descriptor : MessageDescriptor) -> Message {
    var fields = [Field]()

    while (cursor < range.location + range.length) {
      let s = self.nextVarint()
      let tag = s >> 3
      let wiretype = s & 0x07
      let field = descriptor.fieldDescriptor(tag:tag)

      switch (wiretype) {
      case 0: // varint
        var value = self.nextVarint()
        if let field = field {
          if ((field.type == FieldType.SINT32) || (field.type == FieldType.SINT64)) {
            // zigzag decoding
            let sign = value & 0x01
            value = value >> 1
            if sign == 1 {
              value = -value - 1
            }
          }
          fields.append(
            Field(
              descriptor: field,
              value: value
          ))
        }

      case 1: // 64-bit

        if let field = field {
          if field.type == FieldType.DOUBLE {
            let value = self.nextDouble()
            fields.append(
              Field(
                descriptor: field,
                value: value))
          } else {
            let value = self.nextInt64()
              fields.append(
                Field(
                  descriptor: field,
                  value: value))
          }
        }

      case 2: // length-delimited
        let length = self.nextVarint()
        if let field = field {
          switch (field.type) {
          case FieldType.STRING:
            let value = self.nextString(length: length)
            fields.append(
              Field(
                descriptor: field,
                value: value))

          case FieldType.BYTES:
            let value = self.nextData(length: length)
            fields.append(
              Field(
                descriptor: field,
                value: value))

          default:
            if let fieldDescriptor = fileDescriptorSet.messageDescriptor(name:field.type_name) {
              let value = readMessage(range:NSMakeRange(cursor, length),
                                      descriptor: fieldDescriptor)
              fields.append(
                Field(
                  descriptor: field,
                  value: value))
            } else {
              // skip unknown messages
              cursor += length
            }
          }
        } else {
          // skip unknown messages
          cursor += length
        }

      case 3: // start group
        break

      case 4: // end group
        break

      case 5: // 32-bit
        if let field = field {
          if field.type == FieldType.FLOAT {
            let value = self.nextFloat()
            fields.append(
              Field(
                descriptor: field,
                value: value))
          } else {
            let value = self.nextInt32()
            fields.append(
              Field(
                descriptor: field,
                value: value))
          }
        }

      default: continue
      }
    }
    return Message(descriptor:descriptor, fields:fields)
  }
}
