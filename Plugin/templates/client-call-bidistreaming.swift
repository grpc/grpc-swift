// {{ method.name }} (Bidirectional Streaming)
public class {{ .|call:protoFile,service,method }} {
  var call : Call

  /// Create a call.
  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("{{ .|path:protoFile,service,method }}")
  }

  fileprivate func run(metadata:Metadata) throws -> {{ .|call:protoFile,service,method }} {
    try self.call.start(metadata: metadata, completion:{})
    return self
  }

  fileprivate func receiveMessage(callback:@escaping ({{ method|output }}?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = try? {{ method|output }}(protobuf:data) {
          try callback(responseMessage)
        } else {
          try callback(nil) // error, bad data
        }
      } else {
        try callback(nil)
      }
    }
  }

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

  public func Send(_ message:{{ method|input }}) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  public func CloseSend() {
    let done = NSCondition()
    try! call.close() {
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
  }
}
