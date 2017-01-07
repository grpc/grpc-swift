// {{ method.name }} (Client Streaming)
public class {{ .|call:protoFile,service,method }} {
  private var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  // Call this to start a call.
  fileprivate func run(metadata:Metadata) throws -> {{ .|call:protoFile,service,method }} {
    try self.call.start(metadata: metadata, completion:{})
    return self
  }

  // Call this to send each message in the request stream.
  public func Send(_ message: {{ method|input }}) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  // Call this to close the connection and wait for a response. Blocks.
  public func CloseAndReceive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:protoFile,service }}?
    var returnMessage : {{ method|output }}!
    let done = NSCondition()

    do {
      try self.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          returnMessage = responseMessage
        } else {
          returnError = {{ .|clienterror:protoFile,service }}.invalidMessageReceived
        }
        done.lock()
        done.signal()
        done.unlock()
      }
      try call.close(completion:{
        print("closed")
      })
      done.lock()
      done.wait()
      done.unlock()
    } catch (let error) {
      print("ERROR B: \(error)")
    }

    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  // Call this to receive a message.
  // The callback will be called when a message is received.
  // call this again from the callback to wait for another message.
  fileprivate func receiveMessage(callback:@escaping ({{ method|output }}?) throws -> Void)
    throws {
      try call.receiveMessage() {(data) in
        guard let data = data else {
          try callback(nil)
          return
        }
        guard
          let responseMessage = try? {{ method|output }}(protobuf:data)
          else {
            return
        }
        try callback(responseMessage)
      }
  }

}
