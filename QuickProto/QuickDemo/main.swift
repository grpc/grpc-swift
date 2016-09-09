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

// read and write protos without generated code
//  1. READING
//  - load a FileDescriptorSet describing a message to be read
//  - read that message into a standard container
//  - access message fields using methods of that container
//  2. WRITING
//  - load a FileDescriptorSet describing a proto to be written
//  - use a standard container to add and set message fields
//  - use the container to write the message

// applications
//  - dynamic proto inspection
//  - testing
//  - quick app development without requiring code generation

// From https://developers.google.com/protocol-buffers/docs/techniques#self-description:
//   "All that said, the reason that this functionality is not included in the Protocol
//    Buffer library is because we have never had a use for it inside Google"

// where am I?
func whereami() {
  let fileManager = FileManager.default
  if (!fileManager.fileExists(atPath:"Samples")) {
    print("\nThis tool should be run from the project directory that contains \"Samples\".")
    print("\nSet the working directory in Xcode with:")
    print("  \"Edit Scheme...\">\"Run\">\"Options\">\"Working Directory\".")
    let path = fileManager.currentDirectoryPath
    print("\nCurrent directory:")
    print("  " + path + "\n")

    exit(0)
  }
}
whereami()

// This generates a data description of FileDescriptorSets that can be used to read them
func regenerate() {
  if let descriptorProto = NSData(contentsOfFile:"Samples/descriptor.out") {
    if let descriptorMessage = FileDescriptorSet().readMessage(name:"FileDescriptorSet",
                                                               proto:descriptorProto as Data) {
      let builder = CodeBuilder(descriptorMessage)
      do {
        try builder.string().write(toFile:"_FileDescriptor.swift",
                                   atomically:false,
                                   encoding: String.Encoding.utf8)
      } catch let err as NSError {
        print(err)
      }
      descriptorMessage.display()
    }
  }
}
regenerate()

func stickynote_reader() {
  if let fileDescriptorSetProto = NSData(contentsOfFile:"Samples/stickynote.out") {
    // load a FileDescriptorSet that includes a descriptor for the message to be read
    let fileDescriptorSet = FileDescriptorSet(proto:fileDescriptorSetProto as Data)

    // load a proto with the specified message descriptor
    if let messageProto = NSData(contentsOfFile: "Samples/StickyNoteRequest.bin") {
      if let message = fileDescriptorSet.readMessage(name:"StickyNoteRequest",
                                                     proto:messageProto as Data) {

        // display the message
        message.display()
        message.forOneField(name:"message") {(field) in print(field.string())}
      }
    }
  }
}
stickynote_reader()

func sample_reader() {
  if let fileDescriptorSetProto = NSData(contentsOfFile:"Samples/sample.out") {
    // load a FileDescriptorSet that includes a descriptor for the message to be read
    let fileDescriptorSet = FileDescriptorSet(proto:fileDescriptorSetProto as Data)

    // load a proto with the specified message descriptor
    if let messageProto = NSData(contentsOfFile:"Samples/SampleMessage.bin") {
      if let message = fileDescriptorSet.readMessage(name:"SampleMessage",
                                                     proto:messageProto as Data) {

        // display the message
        message.display()
        message.forOneField(name:"text") {(field) in print(field.string())}
      }
    }
  }
}
sample_reader()

func sample_writer() {
  if let fileDescriptorSetProto = NSData(contentsOfFile:"Samples/sample.out") {
    // load a FileDescriptorSet that includes a descriptor for the message to be created
    let fileDescriptorSet = FileDescriptorSet(proto:fileDescriptorSetProto as Data)

    // construct an internal representation of the message
    if let message = fileDescriptorSet.createMessage(name:"SampleMessage") {
      message.addField(name:"d") {(field) in field.setDouble(-12.34)}
      message.addField(name:"f") {(field) in field.setFloat(-56.78)}
      message.addField(name:"i64") {(field) in field.setInt(123)}
      message.addField(name:"ui64") {(field) in field.setInt(123456)}
      message.addField(name:"i32") {(field) in field.setInt(123)}
      message.addField(name:"f64") {(field) in field.setInt(123)}
      message.addField(name:"f32") {(field) in field.setInt(123)}
      message.addField(name:"b") {(field) in field.setBool(true)}
      message.addField(name:"text") {(field) in field.setString("hello, world")}
      message.addField(name:"message") {(field) in
        let innerMessage = fileDescriptorSet.createMessage(name:"SampleMessage")!
        innerMessage.addField(name:"text") {(field) in field.setString("inner message")}
        innerMessage.addField(name:"i32") {(field) in field.setInt(54321)}
        innerMessage.addField(name:"message") {(field) in
          let innermostMessage = fileDescriptorSet.createMessage(name:"SampleMessage")!
          innermostMessage.addField(name:"text") {(field) in field.setString("innermost message")}
          innermostMessage.addField(name:"i32") {(field) in field.setInt(12345)}
          field.setMessage(innermostMessage)
        }
        field.setMessage(innerMessage)
      }
      message.addField(name:"data") {(field) in
        let data = "ABCDEFG 123".data(using: .utf8)!
        field.setData(data)
      }
      message.addField(name:"ui32") {(field) in field.setInt(123456)}
      message.addField(name:"sf32") {(field) in field.setInt(123456)}
      message.addField(name:"sf64") {(field) in field.setInt(123456)}
      message.addField(name:"si32") {(field) in field.setInt(-123)}
      message.addField(name:"si64") {(field) in field.setInt(-123)}
      message.display()

      // write the message as a protocol buffer
      let data = message.serialize()
      NSData(data:data).write(toFile: "SampleRequest.out", atomically: false)

      // re-read it
      if let message = fileDescriptorSet.readMessage(name:"SampleMessage",
                                                     proto:data) {

        // display the message
        print("REDISPLAY")
        message.display()
        message.forOneField(name:"text") {(field) in print(field.string())}
      }
    }
  }
}
sample_writer()


