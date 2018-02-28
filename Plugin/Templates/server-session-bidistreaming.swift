// {{ method|methodDescriptorName }} (Bidirectional Streaming)
{{ access }} protocol {{ .|session:file,service,method }} : {{ .|service:file,service }}Session {
  /// Receive a message. Blocks until a message is received or the client closes the connection.
  func receive() throws -> {{ method|input }}

  /// Send a message. Nonblocking.
  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws
  
  /// Close a connection. Blocks until the connection is closed.
  func close() throws
}

fileprivate final class {{ .|session:file,service,method }}Impl : {{ .|service:file,service }}SessionImpl, {{ .|session:file,service,method }} {
  private var provider : {{ .|provider:file,service }}

  /// Create a session.
  init(handler:Handler, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  func receive() throws -> {{ method|input }} {
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

  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws {
    try handler.sendResponse(message:response.serializedData()) {completion()}
  }

  func close() throws {
    let sem = DispatchSemaphore(value: 0)
    try self.handler.sendStatus(statusCode:self.statusCode,
                                statusMessage:self.statusMessage,
                                trailingMetadata:self.trailingMetadata) {
                                  sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }

  /// Run the session. Internal.
  func run(queue:DispatchQueue) throws {
    try self.handler.sendMetadata(initialMetadata:initialMetadata) {
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

//-{% if generateTestStubs %}
/// Simple fake implementation of {{ .|session:file,service,method }} that returns a previously-defined set of results
/// and stores sent values for later verification.
class {{ .|session:file,service,method }}TestStub : {{ .|service:file,service }}SessionTestStub, {{ .|session:file,service,method }} {
  var inputs: [{{ method|input }}] = []
  var outputs: [{{ method|output }}] = []

  func receive() throws -> {{ method|input }} {
    if let input = inputs.first {
      inputs.removeFirst()
      return input
    } else {
      throw {{ .|clienterror:file,service }}.endOfStream
    }
  }

  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws {
    outputs.append(response)
  }

  func close() throws { }
}
//-{% endif %}
