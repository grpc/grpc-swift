// {{ method.name }} (Client Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  // Call this to start a call.
  fileprivate func run(metadata:Metadata) throws -> {{ .|call:protoFile,service,method }} {
    let latch = CountDownLatch(1)
    try self.call.start(.clientStreaming,
                        metadata:metadata)
    {callResult in
      latch.signal()
    }
    latch.wait()
    return self
  }

  // Call this to send each message in the request stream.
  public func send(_ message: {{ method|input }}) throws {
    let messageData = try message.serializeProtobuf()
    try call.sendMessage(data:messageData)
  }

  // Call this to close the connection and wait for a response. Blocks.
  public func closeAndReceive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var returnResponse : {{ method|output }}!
    let latch = CountDownLatch(1)
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData,
          let response = try? {{ method|output }}(protobuf:responseData) {
          returnResponse = response
        } else {
          returnError = {{ .|clienterror:protoFile,service }}.invalidMessageReceived
        }
        latch.signal()
      }
      try call.close(completion:{})
      latch.wait()
    } catch (let error) {
      throw error
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnResponse
  }
}
