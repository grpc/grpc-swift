// server streaming
public class {{ .|session:protoFile,service,method }} {
  var handler : gRPC.Handler
  var provider : {{ .|provider:protoFile,service }}

  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.handler = handler
    self.provider = provider
  }

  public func Send(_ response: {{ method|output }}) throws {
    try! handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      try self.handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! {{ method|input }}(protobuf:requestData)
          // to keep providers from blocking the server thread,
          // we dispatch them to another queue.
          queue.async {
            try! self.provider.expand(request:requestMessage, session: self)
            try! self.handler.sendStatus(statusCode:0,
                                         statusMessage:"OK",
                                         trailingMetadata:Metadata(),
                                         completion:{})
          }
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}