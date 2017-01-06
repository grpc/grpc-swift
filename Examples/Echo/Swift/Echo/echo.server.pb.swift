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

// all code that follows is to-be-generated

import Foundation
import gRPC

public enum Echo_EchoServerError : Error {
  case endOfStream
}

public protocol Echo_EchoHandler {
  func Get(request : Echo_EchoRequest) throws -> Echo_EchoResponse
  func Collect(session : Echo_EchoCollectSession) throws -> Void
  func Expand(request : Echo_EchoRequest, session : Echo_EchoExpandSession) throws -> Void
  func Update(session : Echo_EchoUpdateSession) throws -> Void
}

// unary
public class Echo_EchoGetSession {
  var connection : gRPC.Handler
  var handler : Echo_EchoHandler

  fileprivate init(connection:gRPC.Handler, handler: Echo_EchoHandler) {
    self.connection = connection
    self.handler = handler
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      try connection.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          let replyMessage = try! self.handler.Get(request:requestMessage)
          try self.connection.sendResponse(message:replyMessage.serializeProtobuf(),
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
public class Echo_EchoExpandSession {
  var connection : gRPC.Handler
  var handler : Echo_EchoHandler

  fileprivate init(connection:gRPC.Handler, handler: Echo_EchoHandler) {
    self.connection = connection
    self.handler = handler
  }

  public func Send(_ response: Echo_EchoResponse) throws {
    try! connection.sendResponse(message:response.serializeProtobuf()) {}
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      try self.connection.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          // to keep handlers from blocking the server thread,
          // we dispatch them to another queue.
          queue.async {
            try! self.handler.Expand(request:requestMessage, session: self)
            try! self.connection.sendStatus(statusCode:0,
                                            statusMessage:"OK",
                                            trailingMetadata:Metadata(),
                                            completion:{})
          }
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// client streaming
public class Echo_EchoCollectSession {
  var connection : gRPC.Handler
  var handler : Echo_EchoHandler

  fileprivate init(connection:gRPC.Handler, handler: Echo_EchoHandler) {
    self.connection = connection
    self.handler = handler
  }

  public func Receive() throws -> Echo_EchoRequest {
    print("collect awaiting message")
    let done = NSCondition()
    var requestMessage : Echo_EchoRequest?
    try self.connection.receiveMessage() {(requestData) in
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
      throw Echo_EchoServerError.endOfStream
    }
    return requestMessage!
  }

  public func SendAndClose(_ response: Echo_EchoResponse) throws {
    try! self.connection.sendResponse(message:response.serializeProtobuf(),
                                      statusCode: 0,
                                      statusMessage: "OK",
                                      trailingMetadata: Metadata())
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      print("EchoCollectSession run")
      try self.connection.sendMetadata(initialMetadata:Metadata()) {
        queue.async {
          try! self.handler.Collect(session:self)
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

// fully streaming
public class Echo_EchoUpdateSession {
  var connection : gRPC.Handler
  var handler : Echo_EchoHandler

  fileprivate init(connection:gRPC.Handler, handler: Echo_EchoHandler) {
    self.connection = connection
    self.handler = handler
  }

  public func Receive() throws -> Echo_EchoRequest {
    print("update awaiting message")
    let done = NSCondition()
    var requestMessage : Echo_EchoRequest?
    try self.connection.receiveMessage() {(requestData) in
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
      throw Echo_EchoServerError.endOfStream
    }
    return requestMessage!
  }

  public func Send(_ response: Echo_EchoResponse) throws {
    try connection.sendResponse(message:response.serializeProtobuf()) {}
  }

  public func Close() {
    let done = NSCondition()
    try! self.connection.sendStatus(statusCode: 0,
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

  fileprivate func run(queue:DispatchQueue) {
    do {
      try self.connection.sendMetadata(initialMetadata:Metadata()) {
        queue.async {
          try! self.handler.Update(session:self)
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}

//
// main server for generated service
//
public class Echo_EchoServer {
  private var address: String
  private var server: gRPC.Server
  public var handler: Echo_EchoHandler!

  public init(address:String,
              handler:Echo_EchoHandler) {
    gRPC.initialize()
    self.address = address
    self.handler = handler
    self.server = gRPC.Server(address:address)
  }

  public init?(address:String,
               certificateURL:URL,
               keyURL:URL,
               handler:Echo_EchoHandler) {
    gRPC.initialize()
    self.address = address
    self.handler = handler
    guard
      let certificate = try? String(contentsOf: certificateURL),
      let key = try? String(contentsOf: keyURL)
      else {
        return nil
    }
    self.server = gRPC.Server(address:address, key:key, certs:certificate)
  }

  public func start(queue:DispatchQueue = DispatchQueue.global()) {
    guard let handler = self.handler else {
      assert(false) // the server requires a handler
    }
    server.run {(connection) in
      print("Server received request to " + connection.host
        + " calling " + connection.method
        + " from " + connection.caller)

      switch connection.method {
      case "/echo.Echo/Get":
        Echo_EchoGetSession(connection:connection, handler:handler).run(queue:queue)
      case "/echo.Echo/Expand":
        Echo_EchoExpandSession(connection:connection, handler:handler).run(queue:queue)
      case "/echo.Echo/Collect":
        Echo_EchoCollectSession(connection:connection, handler:handler).run(queue:queue)
      case "/echo.Echo/Update":
        Echo_EchoUpdateSession(connection:connection, handler:handler).run(queue:queue)
      default:
        break // handle unknown requests
      }
    }
  }
}

