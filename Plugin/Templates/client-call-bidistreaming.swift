/// {{ method|methodDescriptorName }} (Bidirectional Streaming)
{{ access }} class {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Call this to start a call. Nonblocking.
  fileprivate func start(metadata:Metadata, completion:@escaping (CallResult)->())
    throws -> {{ .|call:file,service,method }} {
      try self.call.start(.bidiStreaming, metadata:metadata, completion:completion)
      return self
  }

  /// Call this to wait for a result. Blocking.
  {{ access }} func receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:file,service }}?
    var returnMessage : {{ method|output }}!
    let sem = DispatchSemaphore(value: 0)
    do {
      try receive() {response, error in
        returnMessage = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait(timeout: DispatchTime.distantFuture)
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  /// Call this to wait for a result. Nonblocking.
  {{ access }} func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    do {
      try call.receiveMessage() {(data) in
        if let data = data {
          if let returnMessage = try? {{ method|output }}(serializedData:data) {
            completion(returnMessage, nil)
          } else {
            completion(nil, {{ .|clienterror:file,service }}.invalidMessageReceived)
          }
        } else {
          completion(nil, {{ .|clienterror:file,service }}.endOfStream)
        }
      }
    }
  }

  /// Call this to send each message in the request stream.
  {{ access }} func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }

  /// Call this to close the sending connection. Blocking.
  {{ access }} func closeSend() throws {
    let sem = DispatchSemaphore(value: 0)
    try closeSend() {
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }

  /// Call this to close the sending connection. Nonblocking.
  {{ access }} func closeSend(completion:@escaping ()->()) throws {
    try call.close() {
      completion()
    }
  }

  /// Cancel the call.
  {{ access }} func cancel() {
    call.cancel()
  }
}
