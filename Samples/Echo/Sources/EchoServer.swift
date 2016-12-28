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

// This seemed like a nice idea but doesn't work because
// specific message types are in the protocol signatures.
// There are also functions in the Session classes that depend
// on specific message types.

protocol UnaryServer {
  func handle(message:Echo_EchoRequest) -> Echo_EchoResponse?
}

protocol ServerStreamingServer {
  func handle(session:ServerStreamingSession, message:Echo_EchoRequest) -> Void
}

protocol ClientStreamingServer {
  func handle(session:ClientStreamingSession, message:Echo_EchoRequest) -> Void
  func close(session:ClientStreamingSession)
}

protocol BidiStreamingServer {
  func handle(session:BidiStreamingSession, message:Echo_EchoRequest) -> Void
}

// nonstreaming
class UnarySession : Session {
  var handler : Handler
  var server : UnaryServer

  init(handler:Handler, server: UnaryServer) {
    self.handler = handler
    self.server = server
  }

  func run() {
    do {
      try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          if let replyMessage = self.server.handle(message:requestMessage) { // calling stub
            try self.handler.sendResponse(message:replyMessage.serializeProtobuf(),
                                          statusCode: 0,
                                          statusMessage: "OK",
                                          trailingMetadata:Metadata())
          }
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// server streaming
class ServerStreamingSession : Session {
  var handler : Handler
  var server : ServerStreamingServer

  init(handler:Handler, server: ServerStreamingServer) {
    self.handler = handler
    self.server = server
  }

  func sendMessage(message:Echo_EchoResponse) -> Void {
    try! handler.sendResponse(message:message.serializeProtobuf()) {}
  }

  func run() {
    do {
      try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          self.server.handle(session: self, message:requestMessage)
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// client streaming
class ClientStreamingSession : Session {
  var handler : Handler
  var server : ClientStreamingServer

  init(handler:Handler, server: ClientStreamingServer) {
    self.handler = handler
    self.server = server
  }

  func sendMessage(message:Echo_EchoResponse) -> Void {
    try! self.handler.sendResponse(message:message.serializeProtobuf(),
                                   statusCode: 0,
                                   statusMessage: "OK",
                                   trailingMetadata: Metadata())
  }

  func waitForMessage() {
    do {
      try handler.receiveMessage() {(requestData) in
        if let requestData = requestData {

          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          self.waitForMessage()
          self.server.handle(session:self, message:requestMessage)

        } else {
          // if we get an empty message (requestData == nil), we close the connection
          self.server.close(session:self)
        }
      }
    } catch (let error) {
      print(error)
    }
  }

  func run() {
    do {
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        self.waitForMessage()
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// fully streaming
class BidiStreamingSession : Session {
  var handler : Handler
  var server : BidiStreamingServer

  init(handler:Handler, server: BidiStreamingServer) {
    self.handler = handler
    self.server = server
  }

  func sendMessage(message:Echo_EchoResponse) -> Void {
    try! handler.sendResponse(message:message.serializeProtobuf()) {}
  }

  func waitForMessage() {
    do {
      try handler.receiveMessage() {(requestData) in
        if let requestData = requestData {

          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          self.waitForMessage()
          self.server.handle(session:self, message:requestMessage)

        } else {
          // if we get an empty message (requestData == nil), we close the connection
          try self.handler.sendStatus(statusCode: 0,
                                      statusMessage: "OK",
                                      trailingMetadata: Metadata())
          {
            self.handler.shutdown()
          }
        }
      }
    } catch (let error) {
      print(error)
    }
  }

  func run() {
    do {
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        self.waitForMessage()
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

class EchoServer {
  private var address: String
  private var server: Server

  init(address:String, secure:Bool) {
    gRPC.initialize()
    self.address = address
    if secure {
      let certificateURL = URL(fileURLWithPath:"ssl.crt")
      let certificate = try! String(contentsOf: certificateURL)
      let keyURL = URL(fileURLWithPath:"ssl.key")
      let key = try! String(contentsOf: keyURL)
      self.server = gRPC.Server(address:address, key:key, certs:certificate)
    } else {
      self.server = gRPC.Server(address:address)
    }
  }

  func start() {
    print("Server Starting")
    print("GRPC version " + gRPC.version())

    server.run {(handler) in
      print("Server received request to " + handler.host
        + " calling " + handler.method
        + " from " + handler.caller)

      if (handler.method == "/echo.Echo/Get") {
        handler.session = UnarySession(handler:handler,
                                       server:EchoGetServer())
        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Expand") {
        handler.session = ServerStreamingSession(handler:handler,
                                                 server:EchoExpandServer())
        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Collect") {
        handler.session = ClientStreamingSession(handler:handler,
                                                 server:EchoCollectServer())
        handler.session.run()
      }

      else if (handler.method == "/echo.Echo/Update") {
        handler.session = BidiStreamingSession(handler:handler,
                                               server:EchoUpdateServer())
        handler.session.run()
      }
    }
  }
}

// The following code is for developer/users to edit.
// Everything above these lines is intended to be preexisting or generated.

class EchoGetServer : UnaryServer {

  func handle(message:Echo_EchoRequest) -> Echo_EchoResponse? {
    var reply = Echo_EchoResponse()
    reply.text = "Swift echo get: " + message.text
    return reply
  }
}

class EchoExpandServer : ServerStreamingServer {

  func handle(session:ServerStreamingSession, message:Echo_EchoRequest) -> Void {
    let parts = message.text.components(separatedBy: " ")
    var i = 0
    for part in parts {
      var reply = Echo_EchoResponse()
      reply.text = "Swift echo expand (\(i)): \(part)"
      session.sendMessage(message:reply)
      i += 1
      sleep(1)
    }
    var reply = Echo_EchoResponse()
    session.sendMessage(message:reply)
  }
}

class EchoCollectServer : ClientStreamingServer {
  var result = ""

  func handle(session:ClientStreamingSession, message:Echo_EchoRequest) -> Void {
    if result != "" {
      result += " "
    }
    result += message.text
  }

  func close(session:ClientStreamingSession) {
    var reply = Echo_EchoResponse()
    reply.text = "Swift echo collect: " + result
    session.sendMessage(message:reply)
  }
}

class EchoUpdateServer : BidiStreamingServer {
  var i = 0

  func handle(session:BidiStreamingSession, message:Echo_EchoRequest) -> Void {
    var reply = Echo_EchoResponse()
    reply.text = "Swift echo update (\(i)): \(message.text)"
    session.sendMessage(message:reply)
    i += 1
  }
}

