// {{ method.name }} (Server Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  // Call this once with the message to send.
  fileprivate func run(request: {{ method|input }}, metadata: Metadata) throws -> {{ .|call:protoFile,service,method }} {
    let requestData = try request.serializeProtobuf()
    let latch = CountDownLatch(1)
    try call.start(.serverStreaming,
                   metadata:metadata,
                   message:requestData)
    {callResult in
      latch.signal()
    }
    latch.wait()
    return self
  }

  // Call this to wait for a result. Blocks.
  public func receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var response : {{ method|output }}!
    let latch = CountDownLatch(1)
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData {
          response = try? {{ method|output }}(protobuf:responseData)
          if response == nil {
            returnError = {{ .|clienterror:protoFile,service }}.invalidMessageReceived
          }
        } else {
          returnError = {{ .|clienterror:protoFile,service }}.endOfStream
        }
        latch.signal()
      }
      latch.wait()
    }
    if let returnError = returnError {
      throw returnError
    }
    return response
  }
}
