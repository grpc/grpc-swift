/// {{ method.name }} (Client Streaming)
{{ access }} class {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Call this to start a call. Nonblocking.
  fileprivate func start(metadata:Metadata, completion:@escaping (CallResult)->())
    throws -> {{ .|call:file,service,method }} {
      try self.call.start(.clientStreaming, metadata:metadata, completion:completion)
      return self
  }

  /// Call this to send each message in the request stream. Nonblocking.
  {{ access }} func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }

  /// Call this to close the connection and wait for a response. Blocking.
  {{ access }} func closeAndReceive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:file,service }}?
    var returnResponse : {{ method|output }}!
    let sem = DispatchSemaphore(value: 0)
    do {
      try closeAndReceive() {response, error in
        returnResponse = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait(timeout: DispatchTime.distantFuture)
    } catch (let error) {
      throw error
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnResponse
  }

  /// Call this to close the connection and wait for a response. Nonblocking.
  {{ access }} func closeAndReceive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->())
    throws {
      do {
        try call.receiveMessage() {(responseData) in
          if let responseData = responseData,
            let response = try? {{ method|output }}(serializedData:responseData) {
            completion(response, nil)
          } else {
            completion(nil, {{ .|clienterror:file,service }}.invalidMessageReceived)
          }
        }
        try call.close(completion:{})
      } catch (let error) {
        throw error
      }
  }

  /// Cancel the call.
  {{ access }} func cancel() {
    call.cancel()
  }
}
