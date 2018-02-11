// {{ method|methodDescriptorName }} (Server Streaming)
{{ access }} final class {{ .|session:file,service,method }} : {{ .|service:file,service }}Session {
  private var provider : {{ .|provider:file,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  /// Send a message. Nonblocking.
  {{ access }} func send(_ response: {{ method|output }}, completion: @escaping ()->()) throws {
    try handler.sendResponse(message:response.serializedData()) {completion()}
  }

  /// Run the session. Internal.
  fileprivate func run(queue:DispatchQueue) throws {
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
