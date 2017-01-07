// {{ method.name }} (Unary)
public class {{ .|call:protoFile,service,method }} {
  var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  /// Run the call. Blocks until the reply is received.
  fileprivate func run(request: {{ method|input }},
                       metadata: Metadata) throws -> {{ method|output }} {
    let done = NSCondition()
    var callResult : CallResult!
    var responseMessage : {{ method|output }}?
    let requestMessageData = try! request.serializeProtobuf()
    try! call.perform(message: requestMessageData,
                      metadata: metadata)
    {(_callResult) in
      callResult = _callResult
      if let messageData = callResult.resultData {
        responseMessage = try? {{ method|output }}(protobuf:messageData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if let responseMessage = responseMessage {
      return responseMessage
    } else {
      throw {{ .|clienterror:protoFile,service }}.error(c: callResult)
    }
  }
}
