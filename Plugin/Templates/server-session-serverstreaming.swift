// {{ method|methodDescriptorName }} (Server Streaming)
{{ access }} protocol {{ .|session:file,service,method }} : {{ .|service:file,service }}Session {
  /// Send a message. Nonblocking.
  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws
}

fileprivate final class {{ .|session:file,service,method }}Impl : {{ .|service:file,service }}SessionImpl, {{ .|session:file,service,method }} {
  private var provider : {{ .|provider:file,service }}

  /// Create a session.
  init(handler:gRPC.Handler, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws {
    try handler.sendResponse(message:response.serializedData()) {completion()}
  }

  /// Run the session. Internal.
  func run(queue:DispatchQueue) throws {
    try self.handler.receiveMessage(initialMetadata:initialMetadata) {(requestData) in
      if let requestData = requestData {
        do {
          let requestMessage = try {{ method|input }}(serializedData:requestData)
          // to keep providers from blocking the server thread,
          // we dispatch them to another queue.
          queue.async {
            do {
              try self.provider.{{ method|methodDescriptorName|lowercase }}(request:requestMessage, session: self)
              try self.handler.sendStatus(statusCode:self.statusCode,
                                          statusMessage:self.statusMessage,
                                          trailingMetadata:self.trailingMetadata,
                                          completion:{})
            } catch (let error) {
              print("error: \(error)")
            }
          }
        } catch (let error) {
          print("error: \(error)")
        }
      }
    }
  }
}

//-{% if generate_mock_code %}
/// Simple fake implementation of {{ .|session:file,service,method }} that returns a previously-defined set of results
/// and stores sent values for later verification.
class {{ .|session:file,service,method }}Stub : {{ .|service:file,service }}SessionStub, {{ .|session:file,service,method }} {
  var outputs: [{{ method|output }}] = []

  func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws {
    outputs.append(response)
  }

  func close() throws { }
}
//-{% endif %}
