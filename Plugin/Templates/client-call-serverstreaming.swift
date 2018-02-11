/// {{ method|methodDescriptorName }} (Server Streaming)
{{ access }} final class {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Call this once with the message to send. Nonblocking.
  fileprivate func start(request: {{ method|input }},
                         metadata: Metadata,
                         completion: @escaping (CallResult) -> ())
    throws -> {{ .|call:file,service,method }} {
      let requestData = try request.serializedData()
      try call.start(.serverStreaming,
                     metadata:metadata,
                     message:requestData,
                     completion:completion)
      return self
  }

  /// Call this to wait for a result. Blocking.
  {{ access }} func receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:file,service }}?
    var returnResponse : {{ method|output }}!
    let sem = DispatchSemaphore(value: 0)
    do {
      try receive() {response, error in
        returnResponse = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait(timeout: DispatchTime.distantFuture)
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnResponse
  }

  /// Call this to wait for a result. Nonblocking.
  {{ access }} func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData {
          if let response = try? {{ method|output }}(serializedData:responseData) {
            completion(response, nil)
          } else {
            completion(nil, {{ .|clienterror:file,service }}.invalidMessageReceived)
          }
        } else {
          completion(nil, {{ .|clienterror:file,service }}.endOfStream)
        }
      }
    }
  }

  /// Cancel the call.
  {{ access }} func cancel() {
    call.cancel()
  }
}
