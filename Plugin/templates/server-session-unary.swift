// {{ method.name }} (Unary)
public class {{ .|session:protoFile,service,method }} {
  private var handler : gRPC.Handler
  private var provider : {{ .|provider:protoFile,service }}

  /// Create a session.
  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.handler = handler
    self.provider = provider
  }

  /// Run the session. Internal.
  fileprivate func run(queue:DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
      if let requestData = requestData {
        let requestMessage = try {{ method|input }}(protobuf:requestData)
        let replyMessage = try self.provider.get(request:requestMessage)
        try self.handler.sendResponse(message:replyMessage.serializeProtobuf(),
                                      statusCode: 0,
                                      statusMessage: "OK",
                                      trailingMetadata:Metadata())
      }
    }
  }
}
