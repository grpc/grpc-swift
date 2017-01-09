// {{ method.name }} (Bidirectional Streaming)
public class {{ .|session:protoFile,service,method }} {
  private var handler : gRPC.Handler
  private var provider : {{ .|provider:protoFile,service }}

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
        do {
          requestMessage = try {{ method|input }}(protobuf:requestData)
        } catch (let error) {
          print("error \(error)")
        }
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if let requestMessage = requestMessage {
      return requestMessage
    } else {
      throw {{ .|servererror:protoFile,service }}.endOfStream
    }
  }

  /// Send a message. Nonblocking.
  public func Send(_ response: {{ method|output }}) throws {
    try handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  /// Close a connection. Blocks until the connection is closed.
  public func Close() throws {
    let done = NSCondition()
    try self.handler.sendStatus(statusCode: 0,
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
  fileprivate func run(queue:DispatchQueue) throws {
    try self.handler.sendMetadata(initialMetadata:Metadata()) {
      queue.async {
        do {
          try self.provider.{{ method.name|lowercase }}(session:self)
        } catch (let error) {
          print("error \(error)")
        }
      }
    }
  }
}
