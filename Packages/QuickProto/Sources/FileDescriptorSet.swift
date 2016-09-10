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

/// A collection of descriptors that were read from a group of one or more compiled .proto files
public class FileDescriptorSet {
  var fileDescriptors : [FileDescriptor] = []

  public init() { // the base FileDescriptorSet, a FileDescriptorSet for FileDescriptorSet
    fileDescriptors.append(FileDescriptor())
  }

  public init(data:Data) {
    let baseFileDescriptorSet = FileDescriptorSet()
    if let descriptorMessage = baseFileDescriptorSet.readMessage("FileDescriptorSet",
                                                                 data:data) {
      descriptorMessage.forEachField("file") { (field) in
        let fileDescriptor = FileDescriptor(message: field.message())
        fileDescriptors.append(fileDescriptor)
      }
    }
  }

#if !SWIFT_PACKAGE
  convenience public init(filename:String) {
    let path = Bundle.main.resourcePath!.appending("/").appending(filename)
    let fileDescriptorSetProto = NSData(contentsOfFile:path)
    assert(fileDescriptorSetProto != nil) // the file to be loaded must be in the resource bundle
    self.init(data:fileDescriptorSetProto! as Data)
  }
#endif

  init(message:Message) {
    message.forEachField("file") { (field) in
      let fileDescriptor = FileDescriptor(message: field.message())
      fileDescriptors.append(fileDescriptor)
    }
  }

  func messageDescriptor(name: String) -> MessageDescriptor? {
    let parts = name.components(separatedBy: ".")
    let messageName = parts.last!

    for fileDescriptor in fileDescriptors {
      if let messageDescriptor = fileDescriptor.messageDescriptor(name:messageName) {
        return messageDescriptor
      }
    }
    return nil
  }

  public func createMessage(_ name: String) -> Message! {
    if let messageDescriptor = self.messageDescriptor(name: name) {
      return Message(descriptor:messageDescriptor, fields:[])
    } else {
      return nil
    }
  }

  public func readMessage(_ name:String, data:Data) -> Message? {
    let descriptorReader = MessageReader(self,
                                         messageName:name,
                                         data:data)
    let descriptorMessage = descriptorReader.readMessage()
    return descriptorMessage
  }
}
