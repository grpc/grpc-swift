/// {{ method.name }} (Client Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  /// Call this to start a call. Nonblocking.
  fileprivate func start(metadata:Metadata, completion:@escaping (CallResult)->())
    throws -> {{ .|call:protoFile,service,method }} {
      try self.call.start(.clientStreaming, metadata:metadata, completion:completion)
      return self
  }

  /// Call this to send each message in the request stream. Nonblocking.
  public func send(_ message:Echo_EchoRequest, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializeProtobuf()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }

  /// Call this to close the connection and wait for a response. Blocking.
  public func closeAndReceive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
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
  public func closeAndReceive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:protoFile,service }}?)->())
    throws {
      do {
        try call.receiveMessage() {(responseData) in
          if let responseData = responseData,
            let response = try? {{ method|output }}(protobuf:responseData) {
            completion(response, nil)
          } else {
            completion(nil, {{ .|clienterror:protoFile,service }}.invalidMessageReceived)
          }
        }
        try call.close(completion:{})
      } catch (let error) {
        throw error
      }
  }
}
