// {{ method.name }} (Bidirectional Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  fileprivate func run(metadata:Metadata) throws -> {{ .|call:protoFile,service,method }} {
    let latch = CountDownLatch(1)
    try self.call.start(.bidiStreaming,
                        metadata:metadata)
    {callResult in
      latch.signal()
    }
    latch.wait()
    return self
  }

  public func Receive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var returnMessage : {{ method|output }}!
    let latch = CountDownLatch(1)
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
        latch.signal()
      }
      latch.wait()
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  public func Send(_ message:{{ method|input }}) throws {
    let messageData = try message.serializeProtobuf()
    try call.sendMessage(data:messageData)
  }

  public func CloseSend() throws {
    let latch = CountDownLatch(1)
    try call.close() {
      latch.signal()
    }
    latch.wait()
  }
}
