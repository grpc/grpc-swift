//
// {{ method.name }} (Client streaming)
//
public class {{ .|callname:protoFile,service,method }} {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|callpath:protoFile,service,method }}")
  }

  // Call this to start a call.
  fileprivate func run(metadata:Metadata) throws -> Echo_EchoCollectCall {
    try self.call.start(metadata: metadata, completion:{})
    return self
  }

  // Call this to send each message in the request stream.
  public func Send(_ message: Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  // Call this to close the connection and wait for a response. Blocks.
  public func CloseAndReceive() throws -> Echo_EchoResponse {
    var returnError : {{ .|errorname:protoFile,service }}?
    var returnMessage : Echo_EchoResponse!
    let done = NSCondition()

    do {
      try self.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          returnMessage = responseMessage
        } else {
          returnError = {{ .|errorname:protoFile,service }}.invalidMessageReceived
        }
        done.lock()
        done.signal()
        done.unlock()
      }
      try call.close(completion:{
        print("closed")
      })
      done.lock()
      done.wait()
      done.unlock()
    } catch (let error) {
      print("ERROR B: \(error)")
    }

    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  // Call this to receive a message.
  // The callback will be called when a message is received.
  // call this again from the callback to wait for another message.
  fileprivate func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void)
    throws {
      try call.receiveMessage() {(data) in
        guard let data = data else {
          try callback(nil)
          return
        }
        guard
          let responseMessage = try? Echo_EchoResponse(protobuf:data)
          else {
            return
        }
        try callback(responseMessage)
      }
  }

}
