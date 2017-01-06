// unary
public class Echo_EchoGetSession {
  var handler : gRPC.Handler
  var provider : Echo_EchoProvider

  fileprivate init(handler:gRPC.Handler, provider: Echo_EchoProvider) {
    self.handler = handler
    self.provider = provider
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      try handler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
        if let requestData = requestData {
          let requestMessage = try! Echo_EchoRequest(protobuf:requestData)
          let replyMessage = try! self.provider.get(request:requestMessage)
          try self.handler.sendResponse(message:replyMessage.serializeProtobuf(),
                                        statusCode: 0,
                                        statusMessage: "OK",
                                        trailingMetadata:Metadata())

        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}