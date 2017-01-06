//
// {{ method.name }} (Server streaming)
//
public class {{ .|callname:protoFile,service,method }} {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|callpath:protoFile,service,method }}")
  }

  // Call this once with the message to send.
  fileprivate func run(request: {{ method|inputType }}, metadata: Metadata) throws -> {{ .|callname:protoFile,service,method }} {
    let requestMessageData = try! request.serializeProtobuf()
    try! call.startServerStreaming(message: requestMessageData,
                                   metadata: metadata,
                                   completion:{(CallResult) in })
    return self
  }

  // Call this to wait for a result. Blocks.
  public func Receive() throws -> {{ method|outputType }} {
    var returnError : {{ .|errorname:protoFile,service }}?
    var returnMessage : {{ method|outputType }}!
    let done = NSCondition()
    do {
      try call.receiveMessage() {(data) in
        if let data = data {
          returnMessage = try? {{ method|outputType }}(protobuf:data)
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