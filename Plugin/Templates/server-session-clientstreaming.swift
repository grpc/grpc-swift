{{ access }} protocol {{ .|session:file,service,method }}: ServerSessionClientStreaming {
  /// Receive a message. Blocks until a message is received or the client closes the connection.
  func receive() throws -> {{ method|input }}

  /// Send a response and close the connection.
  func sendAndClose(_ response: {{ method|output }}) throws
}

fileprivate final class {{ .|session:file,service,method }}Impl: ServerSessionClientStreamingImpl<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} {}

//-{% if generateTestStubs %}
class {{ .|session:file,service,method }}TestStub: ServerSessionClientStreamingTestStub<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} {}
//-{% endif %}
