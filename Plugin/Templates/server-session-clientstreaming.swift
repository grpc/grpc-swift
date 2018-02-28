// {{ method|methodDescriptorName }} (Client Streaming)
{{ access }} protocol {{ .|session:file,service,method }} : {{ .|service:file,service }}Session {
  /// Receive a message. Blocks until a message is received or the client closes the connection.
  func receive() throws -> {{ method|input }}

  /// Send a response and close the connection.
  func sendAndClose(_ response: {{ method|output }}) throws
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
        requestMessage = try? {{ method|input }}(serializedData:requestData)
      }
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if requestMessage == nil {
      throw {{ .|servererror:file,service }}.endOfStream
    }
    return requestMessage!
  }

  func sendAndClose(_ response: {{ method|output }}) throws {
    try self.handler.sendResponse(message:response.serializedData(),
                                  statusCode:self.statusCode,
                                  statusMessage:self.statusMessage,
                                  trailingMetadata:self.trailingMetadata)
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
class {{ .|session:file,service,method }}TestStub: {{ .|service:file,service }}SessionTestStub, {{ .|session:file,service,method }} {
  var inputs: [{{ method|input }}] = []
  var output: {{ method|output }}?

  func receive() throws -> {{ method|input }} {
    if let input = inputs.first {
      inputs.removeFirst()
      return input
    } else {
      throw {{ .|clienterror:file,service }}.endOfStream
    }
  }

  func sendAndClose(_ response: {{ method|output }}) throws {
    output = response
  }

  func close() throws { }
}
//-{% endif %}
