//
// {{ method.name }} (Server streaming)
//
public class {{ .|callname:protoFile,service,method }} {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|callpath:protoFile,service,method }}")
  }

  // Call this once with the message to send.
  fileprivate func run(request: Echo_EchoRequest, metadata: Metadata) throws -> Echo_EchoExpandCall {
    let requestMessageData = try! request.serializeProtobuf()
    try! call.startServerStreaming(message: requestMessageData,
                                   metadata: metadata,
                                   completion:{(CallResult) in })
    return self
  }

  // Call this to wait for a result. Blocks.
  public func Receive() throws -> Echo_EchoResponse {
    var returnError : {{ .|errorname:protoFile,service }}?
    var returnMessage : Echo_EchoResponse!
    let done = NSCondition()
    do {
      try call.receiveMessage() {(data) in
        if let data = data {
          returnMessage = try? Echo_EchoResponse(protobuf:data)
          if returnMessage == nil {
            returnError = {{ .|errorname:protoFile,service }}.invalidMessageReceived
          }
        } else {
          returnError = {{ .|errorname:protoFile,service }}.endOfStream
        }
        done.lock()
        done.signal()
        done.unlock()
      }
      done.lock()
      done.wait()
      done.unlock()
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }
}
