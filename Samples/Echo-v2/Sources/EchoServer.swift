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
import gRPC
import Darwin // for sleep()

enum ServerError : Error {
  case endOfStream
  case error
}

protocol CustomEchoServer {
  func Get(request : Echo_EchoRequest) throws -> Echo_EchoResponse
  func Collect(stream : EchoCollectSession) throws -> Void
  func Expand(request : Echo_EchoRequest, stream : EchoExpandSession) throws -> Void
  func Update(stream : EchoUpdateSession) throws -> Void
}

// This seemed like a nice idea but doesn't work because
// specific message types are in the protocol signatures.
// There are also functions in the Session classes that depend
// on specific message types.

protocol ServerStreamingServer {
  func handle(session:EchoExpandSession, message:Echo_EchoRequest) -> Void
}

protocol ClientStreamingServer {
  func handle(session:EchoCollectSession, message:Echo_EchoRequest) -> Void
  func close(session:EchoCollectSession)
}

protocol BidiStreamingServer {
  func handle(session:EchoUpdateSession, message:Echo_EchoRequest) -> Void
}

// unary
class EchoGetSession : Session {
  var handler : Handler
  var server : CustomEchoServer

  init(handler:Handler, server: CustomEchoServer) {
    self.handler = handler
    self.server = server
  }

  func run() {
    do {
      try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          let replyMessage = try! self.server.Get(request:requestMessage)
          // calling stub
          try self.handler.sendResponse(message:replyMessage.serializeProtobuf(),
                                        statusCode: 0,
                                        statusMessage: "OK",
                                        trailingMetadata:Metadata())

        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// server streaming
class EchoExpandSession : Session {
  var handler : Handler
  var server : CustomEchoServer

  init(handler:Handler, server: CustomEchoServer) {
    self.handler = handler
    self.server = server
  }

  func Send(_ response: Echo_EchoResponse) throws {
    try! handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  func run() {
    do {
      try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          try self.server.Expand(request:requestMessage, stream: self)
          try! self.handler.sendStatus(statusCode:0,
                                       statusMessage:"OK",
                                       trailingMetadata:Metadata(),
                                       completion:{})
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// client streaming
class EchoCollectSession : Session {
  var handler : Handler
  var server : CustomEchoServer

  init(handler:Handler, server: CustomEchoServer) {
    self.handler = handler
    self.server = server
  }

  func Recv() throws -> Echo_EchoRequest {
    print("collect awaiting message")
    let done = NSCondition()
    var requestMessage : Echo_EchoRequest?
    try self.handler.receiveMessage() {(requestData) in
      print("collect received message")
      if let requestData = requestData {
        requestMessage = try! Echo_EchoRequest(protobuf:requestData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if requestMessage == nil {
      throw ServerError.endOfStream
    }
    return requestMessage!
  }

  func SendAndClose(_ response: Echo_EchoResponse) throws {
    try! self.handler.sendResponse(message:response.serializeProtobuf(),
                                   statusCode: 0,
                                   statusMessage: "OK",
                                   trailingMetadata: Metadata())
  }

  func sendMessage(message:Echo_EchoResponse) -> Void {
    try! self.handler.sendResponse(message:message.serializeProtobuf(),
                                   statusCode: 0,
                                   statusMessage: "OK",
                                   trailingMetadata: Metadata())
  }

  func run() {
    do {
      print("EchoCollectSession run")
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        try self.server.Collect(stream:self)
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// fully streaming
class EchoUpdateSession : Session {
  var handler : Handler
  var server : CustomEchoServer

  init(handler:Handler, server: CustomEchoServer) {
    self.handler = handler
    self.server = server
  }

  func Recv() throws -> Echo_EchoRequest {
    print("update awaiting message")
    let done = NSCondition()
    var requestMessage : Echo_EchoRequest?
    try self.handler.receiveMessage() {(requestData) in
      print("update received message")
      if let requestData = requestData {
        requestMessage = try! Echo_EchoRequest(protobuf:requestData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if requestMessage == nil {
      throw ServerError.endOfStream
    }
    return requestMessage!
  }

  func Send(_ response: Echo_EchoResponse) throws {
    try handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  func sendMessage(message:Echo_EchoResponse) -> Void {
    try! handler.sendResponse(message:message.serializeProtobuf()) {}
  }

  func Close() {
    let done = NSCondition()

    try! self.handler.sendStatus(statusCode: 0,
                                 statusMessage: "OK",
                                 trailingMetadata: Metadata()) {
                                  done.lock()
                                  done.signal()
                                  done.unlock()
    }

    done.lock()
    done.wait()
    done.unlock()
  }

  func run() {
    do {
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        try self.server.Update(stream:self)
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

class EchoServer {
  private var address: String
  private var server: Server

  public var myServer: MyEchoServer!

  init(address:String, secure:Bool) {
    gRPC.initialize()
    self.address = address
    if secure {
      let certificateURL = Bundle.main.url(forResource: "ssl", withExtension: "crt")!

      let certificate = try! String(contentsOf: certificateURL)
      let keyURL = Bundle.main.url(forResource: "ssl", withExtension: "key")!
      let key = try! String(contentsOf: keyURL)
      self.server = gRPC.Server(address:address, key:key, certs:certificate)
    } else {
      self.server = gRPC.Server(address:address)
    }
    self.myServer = MyEchoServer()
  }

  func start() {
    print("Server Starting")
    print("GRPC version " + gRPC.version())

    server.run {(handler) in

      print("Server received request to " + handler.host
        + " calling " + handler.method
        + " from " + handler.caller)

      if (handler.method == "/echo.Echo/Get") {
        handler.session = EchoGetSession(handler:handler,
                                         server:self.myServer)
        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Expand") {
        handler.session = EchoExpandSession(handler:handler,
                                            server:self.myServer)
        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Collect") {
        handler.session = EchoCollectSession(handler:handler,
                                             server:self.myServer)

        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Update") {
        handler.session = EchoUpdateSession(handler:handler,
                                            server:self.myServer)
        handler.session.run()
      }
    }
  }
}

// The following code is for developer/users to edit.
// Everything above these lines is intended to be preexisting or generated.

class MyEchoServer : CustomEchoServer {

  func Get(request : Echo_EchoRequest) throws -> Echo_EchoResponse {
    print("Get received: \(request.text)")
    return Echo_EchoResponse(text:"Swift echo get: " + request.text)
  }

  func Expand(request : Echo_EchoRequest, stream : EchoExpandSession) throws -> Void {
    print("Expand received: \(request.text)")
    let parts = request.text.components(separatedBy: " ")
    var i = 0
    for part in parts {
      try stream.Send(Echo_EchoResponse(text:"Swift echo expand (\(i)): \(part)"))
      i += 1
      sleep(1)
    }
  }

  func Collect(stream : EchoCollectSession) throws -> Void {
    DispatchQueue.global().async {
      print("Called collect")
      var parts : [String] = []
      while true {
        do {
          let request = try stream.Recv()
          print("Collect received: \(request.text)")
          parts.append(request.text)
        } catch ServerError.endOfStream {
          break
        } catch (let error) {
          print("\(error)")
        }
      }
      print("sending collect response")
      let response = Echo_EchoResponse(text:"Swift echo collect: " + parts.joined(separator: " "))
      try! stream.SendAndClose(response)
    }
  }

  func Update(stream : EchoUpdateSession) throws -> Void {
    DispatchQueue.global().async {
      var count = 0
      while true {
        do {
          let request = try stream.Recv()
          print("Update received: \(request.text)")
          count += 1
          try stream.Send(Echo_EchoResponse(text:"Swift echo update (\(count)): \(request.text)"))
        } catch ServerError.endOfStream {
          break
        } catch (let error) {
          
        }
      }
      stream.Close()
    }
  }
}
