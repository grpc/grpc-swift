{{ access }} protocol {{ .|call:file,service,method }}: ClientCallUnary { }

fileprivate final class {{ .|call:file,service,method }}Impl: ClientCallUnaryImpl<{{ method|input }}, {{ method|output }}>, {{ .|call:file,service,method }} {
  override class var method: String { return "{{ .|path:file,service,method }}" }
}
