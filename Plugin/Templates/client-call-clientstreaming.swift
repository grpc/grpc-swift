/// {{ method|methodDescriptorName }} (Client Streaming)
{{ access }} protocol {{ .|call:file,service,method }} {
  /// Call this to send each message in the request stream. Nonblocking.
  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws
  
  /// Call this to close the connection and wait for a response. Blocking.
  func closeAndReceive() throws -> {{ method|output }}
  /// Call this to close the connection and wait for a response. Nonblocking.
  func closeAndReceive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws
  
  /// Cancel the call.
  func cancel()
}

{{ access }} extension {{ .|call:file,service,method }} {
  func closeAndReceive() throws -> {{ method|output }} {
    var returnError : {{ .|clienterror:file,service }}?
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
      try self.call.start(.clientStreaming, metadata:metadata, completion:completion)
      return self
  }

  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }

  func closeAndReceive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData,
          let response = try? {{ method|output }}(serializedData:responseData) {
          completion(response, nil)
        } else {
          completion(nil, {{ .|clienterror:file,service }}.invalidMessageReceived)
        }
      }
      try call.close(completion:{})
    } catch (let error) {
      throw error
    }
  }

  func cancel() {
    call.cancel()
  }
}

//-{% if generateTestStubs %}
/// Simple fake implementation of {{ .|call:file,service,method }}
/// stores sent values for later verification and finall returns a previously-defined result.
class {{ .|call:file,service,method }}TestStub: {{ .|call:file,service,method }} {
  var inputs: [{{ method|input }}] = []
  var output: {{ method|output }}?

  func send(_ message:{{ method|input }}, errorHandler:@escaping (Error)->()) throws {
    inputs.append(message)
  }
  
  func closeAndReceive(completion:@escaping ({{ method|output }}?, {{ .|clienterror:file,service }}?)->()) throws {
    completion(output!, nil)
  }

  func cancel() { }
}
//-{% endif %}
