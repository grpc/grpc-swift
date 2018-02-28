/// {{ method|methodDescriptorName }} (Bidirectional Streaming)
{{ access }} protocol {{ .|call:file,service,method }} {
  /// Call this to wait for a result. Blocking.
  func receive() throws -> {{ method|output }}
  /// Call this to wait for a result. Nonblocking.
  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws
  
  /// Call this to send each message in the request stream.
  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws
  
  /// Call this to close the sending connection. Blocking.
  func closeSend() throws
  /// Call this to close the sending connection. Nonblocking.
  func closeSend(completion: (()->())?) throws
  
  /// Cancel the call.
  func cancel()
}

{{ access }} extension {{ .|call:file,service,method }} {
  func receive() throws -> {{ method|output }} {
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

  func closeSend() throws {
    let sem = DispatchSemaphore(value: 0)
    try closeSend() {
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }
}

fileprivate final class {{ .|call:file,service,method }}Impl: {{ .|call:file,service,method }} {
  private var call : Call

  /// Create a call.
  init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:file,service,method }}")
  }

  /// Call this to start a call. Nonblocking.
  func start(metadata:Metadata, completion: ((CallResult)->())?)
    throws -> {{ .|call:file,service,method }} {
      try self.call.start(.bidiStreaming, metadata:metadata, completion:completion)
      return self
  }

  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
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

  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }

  func closeSend(completion: (()->())?) throws {
  	try call.close(completion: completion)
  }

  func cancel() {
    call.cancel()
  }
}

//-{% if generateTestStubs %}
/// Simple fake implementation of {{ .|call:file,service,method }} that returns a previously-defined set of results
/// and stores sent values for later verification.
class {{ .|call:file,service,method }}TestStub: {{ .|call:file,service,method }} {
  var inputs: [{{ method|input }}] = []
  var outputs: [{{ method|output }}] = []
  
  func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    if let output = outputs.first {
      outputs.removeFirst()
      completion(output, nil)
    } else {
      completion(nil, {{ .|clienterror:file,service }}.endOfStream)
    }
  }

  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    inputs.append(message)
  }

  func closeSend(completion: (()->())?) throws { completion?() }

  func cancel() { }
}
//-{% endif %}
