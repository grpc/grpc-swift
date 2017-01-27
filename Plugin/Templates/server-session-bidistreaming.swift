// {{ method.name }} (Bidirectional Streaming)
public class {{ .|session:protoFile,service,method }} : {{ .|service:protoFile,service }}Session {
  private var provider : {{ .|provider:protoFile,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  /// Receive a message. Blocks until a message is received or the client closes the connection.
  public func Receive() throws -> {{ method|input }} {
    let latch = CountDownLatch(1)
    var requestMessage : {{ method|input }}?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        do {
          requestMessage = try {{ method|input }}(protobuf:requestData)
        } catch (let error) {
          print("error \(error)")
        }
      }
      latch.signal()
    }
    latch.wait()
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
    let latch = CountDownLatch(1)
    try self.handler.sendStatus(statusCode:self.statusCode,
                                statusMessage:self.statusMessage,
                                trailingMetadata:self.trailingMetadata) {
                                  latch.signal()
    }
    latch.wait()
  }

  /// Run the session. Internal.
  fileprivate func run(queue:DispatchQueue) throws {
    try self.handler.sendMetadata(initialMetadata:initialMetadata) {
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
