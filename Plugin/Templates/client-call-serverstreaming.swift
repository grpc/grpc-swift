/// {{ method.name }} (Server Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  /// Call this once with the message to send. Nonblocking.
  fileprivate func start(request: {{ method|input }},
                         metadata: Metadata,
                         completion: @escaping (CallResult) -> ())
    throws -> {{ .|call:protoFile,service,method }} {
      let requestData = try request.serializeProtobuf()
      try call.start(.serverStreaming,
                     metadata:metadata,
                     message:requestData,
                     completion:completion)
      return self
  }

  /// Call this to wait for a result. Blocking.
  public func receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
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
  public func receive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:protoFile,service }}?)->()) throws {
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData {
          if let response = try? {{ method|output }}(protobuf:responseData) {
            completion(response, nil)
          } else {
            completion(nil, {{ .|clienterror:protoFile,service }}.invalidMessageReceived)
          }
        } else {
          completion(nil, {{ .|clienterror:protoFile,service }}.endOfStream)
        }
      }
    }
  }
}
