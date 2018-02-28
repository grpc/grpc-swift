/// {{ method|methodDescriptorName }} (Client Streaming)
{{ access }} protocol {{ .|call:file,service,method }}: ClientCallClientStreamingBase {
  /// Call this to send each message in the request stream. Nonblocking.
  func send(_ message: {{ method|input }}, errorHandler: @escaping (Error) -> Void) throws
  
  /// Call this to close the connection and wait for a response. Blocking.
  func closeAndReceive() throws -> {{ method|output }}
  /// Call this to close the connection and wait for a response. Nonblocking.
  func closeAndReceive(completion: @escaping ({{ method|output }}?, ClientError?) -> Void) throws
}

fileprivate final class {{ .|call:file,service,method }}Impl: ClientCallClientStreamingImpl<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}

//-{% if generateTestStubs %}
/// Simple fake implementation of {{ .|call:file,service,method }}
/// stores sent values for later verification and finall returns a previously-defined result.
class {{ .|call:file,service,method }}TestStub: ClientCallClientStreamingTestStub<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}
//-{% endif %}
