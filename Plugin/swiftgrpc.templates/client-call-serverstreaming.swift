// {{ method.name }} (Server Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  // Call this once with the message to send.
  fileprivate func run(request: {{ method|input }}, metadata: Metadata) throws -> {{ .|call:protoFile,service,method }} {
    let requestMessageData = try request.serializeProtobuf()
    try call.start(.serverStreaming,
                   metadata:metadata,
                   message:requestMessageData)
    {_ in}
    return self
  }

  // Call this to wait for a result. Blocks.
  public func Receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var returnMessage : {{ method|output }}!
    let done = NSCondition()
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
        done.lock()
        done.signal()
        done.unlock()
      }
      done.lock()
      done.wait()
      done.unlock()
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }
}
