//
// {{ method.name }} (Unary)
//
public class {{ .|callname:protoFile,service,method }} {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|callpath:protoFile,service,method }}")
  }

  fileprivate func run(request: {{ method|inputType }},
                       metadata: Metadata) throws -> {{ method|outputType }} {
    let done = NSCondition()
    var callResult : CallResult!
    var responseMessage : {{ method|outputType }}?
    let requestMessageData = try! request.serializeProtobuf()
    try! call.perform(message: requestMessageData,
                      metadata: metadata)
    {(_callResult) in
      callResult = _callResult
      if let messageData = callResult.resultData {
        responseMessage = try? {{ method|outputType }}(protobuf:messageData)
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
      throw {{ .|errorname:protoFile,service }}.error(c: callResult)
    }
  }
}