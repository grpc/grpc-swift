/// {{ method|methodDescriptorName }} (Server Streaming)
{{ access }} protocol {{ .|call:file,service,method }} {
  /// Call this to wait for a result. Blocking.
  func receive() throws -> {{ method|output }}
  /// Call this to wait for a result. Nonblocking.
  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws
  
  /// Cancel the call.
  func cancel()
}

{{ access }} extension {{ .|call:file,service,method }} {
  func receive() throws -> {{ method|output }} {
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
}

fileprivate final class {{ .|call:file,service,method }}Impl: {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Call this once with the message to send. Nonblocking.
  func start(request: {{ method|input }},
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

  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
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
  func cancel() {
    call.cancel()
  }
}

//-{% if generate_mock_code %}
/// Simple fake implementation of {{ .|call:file,service,method }} that returns a previously-defined set of results.
class {{ .|call:file,service,method }}Stub: {{ .|call:file,service,method }} {
  var outputs: [{{ method|output }}] = []
  
  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    if let output = outputs.first {
      outputs.removeFirst()
      completion(output, nil)
    } else {
      completion(nil, {{ .|clienterror:file,service }}.endOfStream)
    }
  }

  func cancel() { }
}
//-{% endif %}
