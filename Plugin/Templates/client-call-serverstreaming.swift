{{ access }} protocol {{ .|call:file,service,method }}: ClientCallServerStreaming {
  /// Call this to wait for a result. Blocking.
  func receive() throws -> {{ method|output }}
  /// Call this to wait for a result. Nonblocking.
  func receive(completion: @escaping ({{ method|output }}?, ClientError?) -> Void) throws
}

fileprivate final class {{ .|call:file,service,method }}Base: ClientCallServerStreamingBase<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}

//-{% if generateTestStubs %}
class {{ .|call:file,service,method }}TestStub: ClientCallServerStreamingTestStub<{{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}
//-{% endif %}
