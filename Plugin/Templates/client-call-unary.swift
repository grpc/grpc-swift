// {{ method.name }} (Unary)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  /// Run the call. Blocks until the reply is received.
  fileprivate func run(request: {{ method|input }},
                       metadata: Metadata) throws -> {{ method|output }} {
    let done = NSCondition()
    var callResult : CallResult!
    var response : {{ method|output }}?
    let requestData = try request.serializeProtobuf()
    try call.start(.unary,
                   metadata:metadata,
                   message:requestData)
    {(_callResult) in
      callResult = _callResult
      if let responseData = callResult.resultData {
        response = try? {{ method|output }}(protobuf:responseData)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    if let response = response {
      return response
    } else {
      throw {{ .|clienterror:protoFile,service }}.error(c: callResult)
    }
  }
}
