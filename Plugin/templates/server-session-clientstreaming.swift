// client streaming
public class {{ .|session:protoFile,service,method }} {
  var handler : gRPC.Handler
  var provider : {{ .|provider:protoFile,service }}

  fileprivate init(handler:gRPC.Handler, provider: {{ .|provider:protoFile,service }}) {
    self.handler = handler
    self.provider = provider
  }

  public func Receive() throws -> {{ method|input }} {
    let done = NSCondition()
    var requestMessage : {{ method|input }}?
    try self.handler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        requestMessage = try! {{ method|input }}(protobuf:requestData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if requestMessage == nil {
      throw {{ .|servererror:protoFile,service }}.endOfStream
    }
    return requestMessage!
  }

  public func SendAndClose(_ response: {{ method|output }}) throws {
    try! self.handler.sendResponse(message:response.serializeProtobuf(),
                                   statusCode: 0,
                                   statusMessage: "OK",
                                   trailingMetadata: Metadata())
  }

  fileprivate func run(queue:DispatchQueue) {
    do {
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