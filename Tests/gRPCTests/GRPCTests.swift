import XCTest
@testable import gRPC

class gRPCTests: XCTestCase {

  func testBasicSanity() {
    gRPC.initialize()
    let done = NSCondition()
    DispatchQueue.global().async() {
      server()
      done.lock()
      done.signal()
      done.unlock()
    }
    DispatchQueue.global().async() {
      client()
    }
    done.lock()
    done.wait()
    done.unlock()
  }
}

extension gRPCTests {
  static var allTests : [(String, (gRPCTests) -> () throws -> Void)] {
    return [
      ("testBasicSanity", testBasicSanity),
    ]
  }
}

let address = "localhost:8999"
let host = "foo.test.google.fr"
let clientText = "hello, server!"
let serverText = "hello, client!"
let initialClientMetadata =
  ["x": "xylophone",
   "y": "yu",
   "z": "zither"]
let initialServerMetadata =
  ["a": "Apple",
   "b": "Banana",
   "c": "Cherry"]
let trailingServerMetadata =
  ["0": "zero",
   "1": "one",
   "2": "two"]
let steps = 30
let hello = "/hello"
let goodbye = "/goodbye"
let statusCode = 0
let statusMessage = "OK"

func verify_metadata(_ metadata: Metadata, expected: [String:String]) {
  XCTAssertGreaterThanOrEqual(metadata.count(), expected.count)
  for i in 0..<metadata.count() {
    if expected[metadata.key(i)] != nil {
      XCTAssertEqual(metadata.value(i), expected[metadata.key(i)])
    }
  }
}

func client() {
  let message = clientText.data(using: .utf8)
  let c = gRPC.Channel(address:address)
  c.host = host
  for i in 0..<steps {
    let done = NSCondition()
    do {
      let method = (i < steps-1) ? hello : goodbye
      let call = c.makeCall(method)
      let metadata = Metadata(initialClientMetadata)
      try call.perform(message: message!, metadata:metadata) {
        (response) in
        // verify the basic response from the server
        XCTAssertEqual(response.statusCode, statusCode)
        XCTAssertEqual(response.statusMessage, statusMessage)
        // verify the message from the server
        let resultData = response.resultData
        let messageString = String(data: resultData!, encoding: .utf8)
        XCTAssertEqual(messageString, serverText)
        // verify the initial metadata from the server
        let initialMetadata = response.initialMetadata!
        verify_metadata(initialMetadata, expected: initialServerMetadata)
        // verify the trailing metadata from the server
        let trailingMetadata = response.trailingMetadata!
        verify_metadata(trailingMetadata, expected: trailingServerMetadata)
        done.lock()
        done.signal()
        done.unlock()
      }
    } catch (let error) {
        XCTFail("error \(error)")
    }
    // wait for the call to complete
    done.lock()
    done.wait()
    done.unlock()
  }
}

func server() {
  let server = gRPC.Server(address:address)
  var requestCount = 0
  let done = NSCondition()
  server.run() {(requestHandler) in
    do {
      requestCount += 1
      XCTAssertEqual(requestHandler.host, host)
      if (requestCount < steps) {
        XCTAssertEqual(requestHandler.method, hello)
      } else {
        XCTAssertEqual(requestHandler.method, goodbye)
      }
      let initialMetadata = requestHandler.requestMetadata
      verify_metadata(initialMetadata, expected: initialClientMetadata)
      let initialMetadataToSend = Metadata(initialServerMetadata)
      try requestHandler.receiveMessage(initialMetadata:initialMetadataToSend)
      {(messageData) in
        let messageString = String(data: messageData!, encoding: .utf8)
        XCTAssertEqual(messageString, clientText)
      }
      if requestHandler.method == goodbye {
        // exit the server thread
        done.lock()
        done.signal()
        done.unlock()
      }
      let replyMessage = serverText
      let trailingMetadataToSend = Metadata(trailingServerMetadata)
      try requestHandler.sendResponse(message:replyMessage.data(using: .utf8)!,
                                      statusCode:statusCode,
                                      statusMessage:statusMessage,
                                      trailingMetadata:trailingMetadataToSend)
    } catch (let error) {
      XCTFail("error \(error)")
    }
  }
  // wait for the server to exit
  done.lock()
  done.wait()
  done.unlock()
}

