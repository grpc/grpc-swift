/// {{ method|methodDescriptorName }} (Unary)
{{ access }} protocol {{ .|call:file,service,method }} {
  /// Cancel the call.
  func cancel()
}

/// {{ method|methodDescriptorName }} (Unary)
fileprivate final class {{ .|call:file,service,method }}Impl: {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Run the call. Blocks until the reply is received.
  /// - Throws: `BinaryEncodingError` if encoding fails. `CallError` if fails to call. `{{ .|clienterror:file,service }}` if receives no response.
  func run(request: {{ method|input }},
                       metadata: Metadata) throws -> {{ method|output }} {
    let sem = DispatchSemaphore(value: 0)
    var returnCallResult : CallResult!
    var returnResponse : {{ method|output }}?
    _ = try start(request:request, metadata:metadata) {response, callResult in
      returnResponse = response
      returnCallResult = callResult
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if let returnResponse = returnResponse {
      return returnResponse
    } else {
      throw {{ .|clienterror:file,service }}.error(c: returnCallResult)
    }
  }

  /// Start the call. Nonblocking.
  /// - Throws: `BinaryEncodingError` if encoding fails. `CallError` if fails to call.
  func start(request: {{ method|input }},
                         metadata: Metadata,
                         completion: @escaping (({{ method|output }}?, CallResult)->()))
    throws -> {{ .|call:file,service,method }} {

      let requestData = try request.serializedData()
      try call.start(.unary,
                     metadata:metadata,
                     message:requestData)
      {(callResult) in
        if let responseData = callResult.resultData,
          let response = try? {{ method|output }}(serializedData:responseData) {
          completion(response, callResult)
        } else {
          completion(nil, callResult)
        }
      }
      return self
  }

  func cancel() {
    call.cancel()
  }
}
