// {{ method|methodDescriptorName }} (Bidirectional Streaming)
{{ access }} final class {{ .|session:file,service,method }} : {{ .|service:file,service }}Session {
  private var provider : {{ .|provider:file,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  /// Receive a message. Blocks until a message is received or the client closes the connection.
  {{ access }} func receive() throws -> {{ method|input }} {
    let sem = DispatchSemaphore(value: 0)
    var requestMessage : {{ method|input }}?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        do {
          requestMessage = try {{ method|input }}(serializedData:requestData)
        } catch (let error) {
          print("error \(error)")
        }
      }
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if let requestMessage = requestMessage {
      return requestMessage
    } else {
      throw {{ .|servererror:file,service }}.endOfStream
    }
  }

  /// Send a message. Nonblocking.
  {{ access }} func send(_ response: {{ method|output }}, completion: ((Bool)->())?) throws {
	try handler.sendResponse(message:response.serializedData(), completion: completion)
  }

  /// Close a connection. Blocks until the connection is closed.
  {{ access }} func close() throws {
    let sem = DispatchSemaphore(value: 0)
    try self.handler.sendStatus(statusCode:self.statusCode,
                                statusMessage:self.statusMessage,
                                trailingMetadata:self.trailingMetadata) { _ in sem.signal() }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }

  /// Run the session. Internal.
  fileprivate func run(queue:DispatchQueue) throws {
    try self.handler.sendMetadata(initialMetadata:initialMetadata) { _ in
      queue.async {
        do {
          try self.provider.{{ method|methodDescriptorName|lowercase }}(session:self)
        } catch (let error) {
          print("error \(error)")
        }
      }
    }
  }
}
