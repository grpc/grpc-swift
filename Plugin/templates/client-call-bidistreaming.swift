//
// {{ method.name }} (Bidirectional streaming)
//
public class {{ .|callname:protoFile,service,method }} {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|callpath:protoFile,service,method }}")
  }

  fileprivate func run(metadata:Metadata) throws -> Echo_EchoUpdateCall {
    try self.call.start(metadata: metadata, completion:{})
    return self
  }

  fileprivate func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = try? Echo_EchoResponse(protobuf:data) {
          try callback(responseMessage)
        } else {
          try callback(nil) // error, bad data
        }
      } else {
        try callback(nil)
      }
    }
  }

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

  public func Send(_ message:Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  public func CloseSend() {
    let done = NSCondition()
    try! call.close() {
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
  }
}
