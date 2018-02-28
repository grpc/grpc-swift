//-{% for service in file.services %}
/// To build a server, implement a class that conforms to this protocol.
{{ access }} protocol {{ .|provider:file,service }} {
  //-{% for method in service.methods %}
  //-{% if method|methodIsUnary %}
  func {{ method|methodDescriptorName|lowercase }}(request : {{ method|input }}, session : {{ .|session:file,service,method }}) throws -> {{ method|output }}
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  func {{ method|methodDescriptorName|lowercase }}(request : {{ method|input }}, session : {{ .|session:file,service,method }}) throws
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  func {{ method|methodDescriptorName|lowercase }}(session : {{ .|session:file,service,method }}) throws
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  func {{ method|methodDescriptorName|lowercase }}(session : {{ .|session:file,service,method }}) throws
  //-{% endif %}
  //-{% endfor %}
}

//-{% for method in service.methods %}
//-{% if method|methodIsUnary %}
//-{% include "server-session-unary.swift" %}
//-{% endif %}
//-{% if method|methodIsServerStreaming %}
//-{% include "server-session-serverstreaming.swift" %}
//-{% endif %}
//-{% if method|methodIsClientStreaming %}
//-{% include "server-session-clientstreaming.swift" %}
//-{% endif %}
//-{% if method|methodIsBidiStreaming %}
//-{% include "server-session-bidistreaming.swift" %}
//-{% endif %}
//-{% endfor %}

/// Main server for generated service
{{ access }} final class {{ .|server:file,service }}: ServiceServer {
  private var provider: {{ .|provider:file,service }}

  {{ access }} init(address: String, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(address: address)
  }

  {{ access }} init?(address: String, certificateURL: URL, keyURL: URL, provider: {{ .|provider:file,service }}) {
    self.provider = provider
    super.init(address: address, certificateURL: certificateURL, keyURL: keyURL)
  }

  /// Start the server.
  {{ access }} override func handleMethod(_ method: String, handler: Handler, queue: DispatchQueue) throws -> Bool {
    let provider = self.provider
    switch method {
    //-{% for method in service.methods %}
    case "{{ .|path:file,service,method }}":
      //-{% if method|methodIsUnary or method|methodIsServerStreaming %}
      try {{ .|session:file,service,method }}Impl(
        handler: handler,
        providerBlock: { try provider.{{ method|methodDescriptorName|lowercase }}(request: $0, session: $1 as! {{ .|session:file,service,method }}Impl) })
          .run(queue: queue)
      //-{% else %}
      try {{ .|session:file,service,method }}Impl(
        handler: handler,
        providerBlock: { try provider.{{ method|methodDescriptorName|lowercase }}(session: $0 as! {{ .|session:file,service,method }}Impl) })
          .run(queue: queue)
      //-{% endif %}
      return true
    //-{% endfor %}
    default:
      return false
    }
  }
}
//-{% endfor %}
