{{ access }} protocol {{ .|session:file,service,method }}: ServerSessionBidirectionalStreaming {
  /// Receive a message. Blocks until a message is received or the client closes the connection.
  func receive() throws -> {{ method|input }}

  /// Send a message. Nonblocking.
  func send(_ response: {{ method|output }}, completion: ((Bool) -> Void)?) throws

  /// Close a connection. Blocks until the connection is closed.
  func close() throws
}

fileprivate final class {{ .|session:file,service,method }}Base: ServerSessionBidirectionalStreamingBase<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} {}

//-{% if generateTestStubs %}
class {{ .|session:file,service,method }}TestStub: ServerSessionBidirectionalStreamingTestStub<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} {}
//-{% endif %}
