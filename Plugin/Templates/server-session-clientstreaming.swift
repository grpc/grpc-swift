// {{ method.name }} (Client Streaming)
public class {{ .|session:protoFile,service,method }} : {{ .|service:protoFile,service }}Session {
  private var provider : {{ .|provider:protoFile,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  /// Receive a message. Blocks until a message is received or the client closes the connection.
  public func receive() throws -> {{ method|input }} {
    let sem = DispatchSemaphore(value: 0)
    var requestMessage : {{ method|input }}?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        requestMessage = try? {{ method|input }}(protobuf:requestData)
      }
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if requestMessage == nil {
      throw {{ .|servererror:protoFile,service }}.endOfStream
    }
    return requestMessage!
  }

  /// Send a response and close the connection.
  public func sendAndClose(_ response: {{ method|output }}) throws {
    try self.handler.sendResponse(message:response.serializeProtobuf(),
                                  statusCode:self.statusCode,
                                  statusMessage:self.statusMessage,
                                  trailingMetadata:self.trailingMetadata)
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
