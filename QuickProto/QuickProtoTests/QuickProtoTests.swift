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
import XCTest

class QuickProtoTests: XCTestCase {

  func testSampleMessageRead() {
    let myBundle = Bundle.init(for: type(of:self))
    let sampleProtoURL = myBundle.url(forResource: "sample", withExtension: "out")
    let sampleMessageURL = myBundle.url(forResource: "SampleMessage", withExtension: "bin")
    if let sampleProtoURL = sampleProtoURL, let sampleMessageURL = sampleMessageURL {

      let sampleProtoData = try! Data(contentsOf: sampleProtoURL)
      let fileDescriptorSet = FileDescriptorSet(proto:sampleProtoData as Data)

      let sampleMessageData = try! Data(contentsOf: sampleMessageURL)
      if let message = fileDescriptorSet.readMessage(name:"SampleMessage", proto:sampleMessageData) {
        XCTAssert(message.fieldCount() == 15)
        XCTAssert(message.oneField(name:"d")!.double() == 1.23)
        XCTAssert(message.oneField(name:"f")!.float() == 4.56)
        XCTAssert(message.oneField(name:"i64")!.integer() == 1234567)
        XCTAssert(message.oneField(name:"ui64")!.integer() == 1234567)
        XCTAssert(message.oneField(name:"i32")!.integer() == 1234)
        XCTAssert(message.oneField(name:"b")!.bool() == true)
        XCTAssert(message.oneField(name:"text")!.string() == "Hello, world!")
        XCTAssert(message.oneField(name:"ui32")!.integer() == 1234)
        XCTAssert(message.oneField(name:"sf32")!.integer() == 1234)
        XCTAssert(message.oneField(name:"sf64")!.integer() == 1234567)
        XCTAssert(message.oneField(name:"si32")!.integer() == 1234)
        XCTAssert(message.oneField(name:"si64")!.integer() == 1234567)
        let inner = message.oneField(name:"message")!.message()
        XCTAssert(inner.oneField(name:"text")!.string() == "ABCDEFG")
        // XCTAssert(inner.oneField(name:"b")!.bool() == false)
        XCTAssert(inner.oneField(name:"si32")!.integer() == -1234)
        XCTAssert(inner.oneField(name:"si64")!.integer() == -1234567)
      }
    } else {
      XCTAssert(false)
    }
  }

  func testSampleRoundtrip() {
    let myBundle = Bundle.init(for: type(of:self))
    let sampleProtoURL = myBundle.url(forResource: "sample", withExtension: "out")
    if let sampleProtoURL = sampleProtoURL {
      let sampleProtoData = try! Data(contentsOf: sampleProtoURL)
      let fileDescriptorSet = FileDescriptorSet(proto:sampleProtoData as Data)
      // construct an internal representation of a message
      let message = fileDescriptorSet.createMessage(name:"SampleMessage")
      XCTAssert(message != nil)
      if let message = message {
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

        // serialize the message as a binary protocol buffer
        let data = message.serialize()

        // re-read it and check fields
        let message2 = fileDescriptorSet.readMessage(name:"SampleMessage", proto:data)!
        XCTAssert(message2.oneField(name:"d")!.double() == -12.34)
        XCTAssert(message2.oneField(name:"f")!.float() == -56.78)
        XCTAssert(message2.oneField(name:"i64")!.integer() == 123)
        XCTAssert(message2.oneField(name:"ui64")!.integer() == 123456)
        XCTAssert(message2.oneField(name:"i32")!.integer() == 123)
        XCTAssert(message2.oneField(name:"f64")!.integer() == 123)
        XCTAssert(message2.oneField(name:"f32")!.integer() == 123)
        XCTAssert(message2.oneField(name:"b")!.bool() == true)
        XCTAssert(message2.oneField(name:"text")!.string() == "hello, world")
        XCTAssert(message2.oneField(name:"ui32")!.integer() == 123456)
        XCTAssert(message2.oneField(name:"sf32")!.integer() == 123456)
        XCTAssert(message2.oneField(name:"sf64")!.integer() == 123456)
        XCTAssert(message2.oneField(name:"si32")!.integer() == -123)
        XCTAssert(message2.oneField(name:"si64")!.integer() == -123)

        let inner2 = message2.oneField(name:"message")!.message()
        XCTAssert(inner2.oneField(name:"text")!.string() == "inner message")
        XCTAssert(inner2.oneField(name:"i32")!.integer() == 54321)

        let inner3 = inner2.oneField(name:"message")!.message()
        XCTAssert(inner3.oneField(name:"text")!.string() == "innermost message")
        XCTAssert(inner3.oneField(name:"i32")!.integer() == 12345)

        let data2 = message2.oneField(name:"data")!.data()
        XCTAssert( String(data: data2, encoding:.utf8) == "ABCDEFG 123")
      }
    }
  }
}
