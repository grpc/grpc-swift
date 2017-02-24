/// {{ method.name }} (Unary)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  /// Run the call. Blocks until the reply is received.
  fileprivate func run(request: {{ method|input }},
                       metadata: Metadata) throws -> {{ method|output }} {
    let sem = DispatchSemaphore(value: 0)
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
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if let response = response {
      return response
    } else {
      throw {{ .|clienterror:protoFile,service }}.error(c: callResult)
    }
  }

  /// Start the call. Nonblocking.
  fileprivate func start(request: {{ method|input }},
                         metadata: Metadata,
                         completion: @escaping ({{ method|output }}?, CallResult)->())
    throws -> {{ .|call:protoFile,service,method }} {

      let requestData = try request.serializeProtobuf()
      try call.start(.unary,
                     metadata:metadata,
                     message:requestData)
      {(callResult) in
        if let responseData = callResult.resultData,
          let response = try? {{ method|output }}(protobuf:responseData) {
          completion(response, callResult)
        } else {
          completion(nil, callResult)
        }
      }
      return self
  }
}
