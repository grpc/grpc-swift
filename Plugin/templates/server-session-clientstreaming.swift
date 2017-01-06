// client streaming
public class Echo_EchoCollectSession {
  var handler : gRPC.Handler
  var provider : Echo_EchoProvider

  fileprivate init(handler:gRPC.Handler, provider: Echo_EchoProvider) {
    self.handler = handler
    self.provider = provider
  }

  public func Receive() throws -> Echo_EchoRequest {
    let done = NSCondition()
    var requestMessage : Echo_EchoRequest?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        requestMessage = try! Echo_EchoRequest(protobuf:requestData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if requestMessage == nil {
      throw Echo_EchoServerError.endOfStream
    }
    return requestMessage!
  }

  public func SendAndClose(_ response: Echo_EchoResponse) throws {
    try! self.handler.sendResponse(message:response.serializeProtobuf(),
                                   statusCode: 0,
                                   statusMessage: "OK",
                                   trailingMetadata: Metadata())
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
      print("EchoCollectSession run")
      try self.handler.sendMetadata(initialMetadata:Metadata()) {
        queue.async {
          try! self.provider.collect(session:self)
        }
      }
    } catch (let callError) {
      print("grpc error: \(callError)")
    }
  }
}