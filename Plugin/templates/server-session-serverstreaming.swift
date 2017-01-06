// server streaming
public class Echo_EchoExpandSession {
  var handler : gRPC.Handler
  var provider : Echo_EchoProvider

  fileprivate init(handler:gRPC.Handler, provider: Echo_EchoProvider) {
    self.handler = handler
    self.provider = provider
  }

  public func Send(_ response: Echo_EchoResponse) throws {
    try! handler.sendResponse(message:response.serializeProtobuf()) {}
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      try self.handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
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