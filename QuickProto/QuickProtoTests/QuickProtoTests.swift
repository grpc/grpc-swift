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
      let fileDescriptorSet = FileDescriptorSet(data:sampleProtoData as Data)

      let sampleMessageData = try! Data(contentsOf: sampleMessageURL)
      if let message = fileDescriptorSet.readMessage("SampleMessage", data:sampleMessageData) {
        XCTAssert(message.fieldCount() == 15)
        XCTAssert(message.oneField("d")!.double() == 1.23)
        XCTAssert(message.oneField("f")!.float() == 4.56)
        XCTAssert(message.oneField("i64")!.integer() == 1234567)
        XCTAssert(message.oneField("ui64")!.integer() == 1234567)
        XCTAssert(message.oneField("i32")!.integer() == 1234)
        XCTAssert(message.oneField("b")!.bool() == true)
        XCTAssert(message.oneField("text")!.string() == "Hello, world!")
        XCTAssert(message.oneField("ui32")!.integer() == 1234)
        XCTAssert(message.oneField("sf32")!.integer() == 1234)
        XCTAssert(message.oneField("sf64")!.integer() == 1234567)
        XCTAssert(message.oneField("si32")!.integer() == 1234)
        XCTAssert(message.oneField("si64")!.integer() == 1234567)
        let inner = message.oneField("message")!.message()
        XCTAssert(inner.oneField("text")!.string() == "ABCDEFG")
        // XCTAssert(inner.oneField("b")!.bool() == false)
        XCTAssert(inner.oneField("si32")!.integer() == -1234)
        XCTAssert(inner.oneField("si64")!.integer() == -1234567)
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
      let fileDescriptorSet = FileDescriptorSet(data:sampleProtoData)
      // construct an internal representation of a message
      let message = fileDescriptorSet.createMessage("SampleMessage")
      XCTAssert(message != nil)
      if let message = message {
        message.addField("d") {(field) in field.setDouble(-12.34)}
        message.addField("f") {(field) in field.setFloat(-56.78)}
        message.addField("i64") {(field) in field.setInt(123)}
        message.addField("ui64") {(field) in field.setInt(123456)}
        message.addField("i32") {(field) in field.setInt(123)}
        message.addField("f64") {(field) in field.setInt(123)}
        message.addField("f32") {(field) in field.setInt(123)}
        message.addField("b") {(field) in field.setBool(true)}
        message.addField("text") {(field) in field.setString("hello, world")}
        message.addField("message") {(field) in
          let innerMessage = fileDescriptorSet.createMessage("SampleMessage")!
          innerMessage.addField("text") {(field) in field.setString("inner message")}
          innerMessage.addField("i32") {(field) in field.setInt(54321)}
          innerMessage.addField("message") {(field) in
            let innermostMessage = fileDescriptorSet.createMessage("SampleMessage")!
            innermostMessage.addField("text") {(field) in field.setString("innermost message")}
            innermostMessage.addField("i32") {(field) in field.setInt(12345)}
            field.setMessage(innermostMessage)
          }
          field.setMessage(innerMessage)
        }
        message.addField("data") {(field) in
          let data = "ABCDEFG 123".data(using: .utf8)!
          field.setData(data)
        }
        message.addField("ui32") {(field) in field.setInt(123456)}
        message.addField("sf32") {(field) in field.setInt(123456)}
        message.addField("sf64") {(field) in field.setInt(123456)}
        message.addField("si32") {(field) in field.setInt(-123)}
        message.addField("si64") {(field) in field.setInt(-123)}

        // serialize the message as a binary protocol buffer
        let data = message.serialize()

        // re-read it and check fields
        let message2 = fileDescriptorSet.readMessage("SampleMessage", data:data)!
        XCTAssert(message2.oneField("d")!.double() == -12.34)
        XCTAssert(message2.oneField("f")!.float() == -56.78)
        XCTAssert(message2.oneField("i64")!.integer() == 123)
        XCTAssert(message2.oneField("ui64")!.integer() == 123456)
        XCTAssert(message2.oneField("i32")!.integer() == 123)
        XCTAssert(message2.oneField("f64")!.integer() == 123)
        XCTAssert(message2.oneField("f32")!.integer() == 123)
        XCTAssert(message2.oneField("b")!.bool() == true)
        XCTAssert(message2.oneField("text")!.string() == "hello, world")
        XCTAssert(message2.oneField("ui32")!.integer() == 123456)
        XCTAssert(message2.oneField("sf32")!.integer() == 123456)
        XCTAssert(message2.oneField("sf64")!.integer() == 123456)
        XCTAssert(message2.oneField("si32")!.integer() == -123)
        XCTAssert(message2.oneField("si64")!.integer() == -123)

        let inner2 = message2.oneField("message")!.message()
        XCTAssert(inner2.oneField("text")!.string() == "inner message")
        XCTAssert(inner2.oneField("i32")!.integer() == 54321)

        let inner3 = inner2.oneField("message")!.message()
        XCTAssert(inner3.oneField("text")!.string() == "innermost message")
        XCTAssert(inner3.oneField("i32")!.integer() == 12345)

        let data2 = message2.oneField("data")!.data()
        XCTAssert( String(data: data2, encoding:.utf8) == "ABCDEFG 123")
      }
    }
  }
}
