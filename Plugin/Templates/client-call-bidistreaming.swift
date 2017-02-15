// {{ method.name }} (Bidirectional Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  fileprivate func run(metadata:Metadata) throws -> {{ .|call:protoFile,service,method }} {
    let sem = DispatchSemaphore(value: 0)
    try self.call.start(.bidiStreaming,
                        metadata:metadata)
    {callResult in
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    return self
  }

  public func receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var returnMessage : {{ method|output }}!
    let sem = DispatchSemaphore(value: 0)
    do {
      try call.receiveMessage() {(data) in
        if let data = data {
          returnMessage = try? {{ method|output }}(protobuf:data)
          if returnMessage == nil {
            returnError = {{ .|clienterror:protoFile,service }}.invalidMessageReceived
          }
        } else {
          returnError = {{ .|clienterror:protoFile,service }}.endOfStream
        }
        sem.signal()
      }
      _ = sem.wait(timeout: DispatchTime.distantFuture)
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  public func send(_ message:{{ method|input }}) throws {
    let messageData = try message.serializeProtobuf()
    try call.sendMessage(data:messageData)
  }

  public func closeSend() throws {
    let sem = DispatchSemaphore(value: 0)
    try call.close() {
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }
}
