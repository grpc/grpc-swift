// {{ method|methodDescriptorName }} (Unary Streaming)
{{ access }} protocol {{ .|session:file,service,method }} : {{ .|service:file,service }}Session { }

fileprivate final class {{ .|session:file,service,method }}Impl : {{ .|service:file,service }}SessionImpl, {{ .|session:file,service,method }} {
  private var provider : {{ .|provider:file,service }}

  /// Create a session.
  init(handler:gRPC.Handler, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(handler:handler)
  }

  /// Run the session. Internal.
  func run(queue:DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata:initialMetadata) {(requestData) in
      if let requestData = requestData {
        let requestMessage = try {{ method|input }}(serializedData:requestData)
        let replyMessage = try self.provider.{{ method|methodDescriptorName|lowercase }}(request:requestMessage, session: self)
        try self.handler.sendResponse(message:replyMessage.serializedData(),
                                      statusCode:self.statusCode,
                                      statusMessage:self.statusMessage,
                                      trailingMetadata:self.trailingMetadata)
      }
    }
  }
}

//-{% if generateTestStubs %}
/// Trivial fake implementation of {{ .|session:file,service,method }}.
class {{ .|session:file,service,method }}TestStub : {{ .|service:file,service }}SessionTestStub, {{ .|session:file,service,method }} { }
//-{% endif %}
