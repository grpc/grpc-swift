{{ access }} protocol {{ .|call:file,service,method }}: ClientCallBidirectionalStreaming {
  /// Call this to wait for a result. Blocking.
  func receive() throws -> {{ method|output }}
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping ({{ method|output }}?, ClientError?) -> Void) throws
  
  /// Call this to send each message in the request stream.
  func send(_ message: {{ method|input }}, errorHandler: @escaping (Error) -> Void) throws
  
  /// Call this to close the sending connection. Blocking.
  func closeSend() throws
  /// Call this to close the sending connection. Nonblocking.
  func closeSend(completion: (() -> Void)?) throws
}

fileprivate final class {{ .|call:file,service,method }}Base: ClientCallBidirectionalStreamingBase<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}

//-{% if generateTestStubs %}
class {{ .|call:file,service,method }}TestStub: ClientCallBidirectionalStreamingTestStub<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}
//-{% endif %}
