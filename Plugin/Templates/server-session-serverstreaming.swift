{{ access }} protocol {{ .|session:file,service,method }}: ServerSessionServerStreaming {
  /// Send a message. Nonblocking.
  func send(_ response: {{ method|output }}, completion: ((Bool) -> Void)?) throws
}

fileprivate final class {{ .|session:file,service,method }}Impl: ServerSessionServerStreamingImpl<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} {}

//-{% if generateTestStubs %}
class {{ .|session:file,service,method }}TestStub: ServerSessionServerStreamingTestStub<{{ method|output }}>, {{ .|session:file,service,method }} {}
//-{% endif %}
