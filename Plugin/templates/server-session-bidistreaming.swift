// {{ method.name }} (Bidirectional Streaming)
public class {{ .|session:protoFile,service,method }} {
  var handler : gRPC.Handler
  var provider : {{ .|provider:protoFile,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.handler = handler
    self.provider = provider
  }

  /// Receive a message. Blocks until a message is received or the client closes the connection.
  public func Receive() throws -> {{ method|input }} {
    let done = NSCondition()
    var requestMessage : {{ method|input }}?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        requestMessage = try! {{ method|input }}(protobuf:requestData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if requestMessage == nil {
      throw {{ .|servererror:protoFile,service }}.endOfStream
    }
    return requestMessage!
  }

  /// Send a message. Nonblocking.
  public func Send(_ response: {{ method|output }}) throws {
    try handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  /// Close a connection. Blocks until the connection is closed.
  public func Close() {
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

  /// Run the session. Internal.
  fileprivate func run(queue:DispatchQueue) {
    do {
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        queue.async {
          try! self.provider.update(session:self)
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}
