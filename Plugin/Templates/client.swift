//-{% for service in file.services %}

//-{% for method in service.methods %}
//-{% if method|methodIsUnary %}
//-{% include "client-call-unary.swift" %}
//-{% endif %}
//-{% if method|methodIsServerStreaming %}
//-{% include "client-call-serverstreaming.swift" %}
//-{% endif %}
//-{% if method|methodIsClientStreaming %}
//-{% include "client-call-clientstreaming.swift" %}
//-{% endif %}
//-{% if method|methodIsBidiStreaming %}
//-{% include "client-call-bidistreaming.swift" %}
//-{% endif %}
//-{% endfor %}

/// Instantiate {{ .|serviceclass:file,service }}Client, then call methods of this protocol to make API calls.
{{ access }} protocol {{ .|serviceclass:file,service }}: ServiceClient {
  //-{% for method in service.methods %}
  //-{% if method|methodIsUnary %}
  /// Synchronous. Unary.
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}) throws -> {{ method|output }}
  /// Asynchronous. Unary.
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: @escaping ({{ method|output }}?, CallResult) -> Void) throws -> {{ .|call:file,service,method }}
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }}
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }}
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }}
  //-{% endif %}

  //-{% endfor %}
}

{{ access }} final class {{ .|serviceclass:file,service }}Client: ServiceClientBase, {{ .|serviceclass:file,service }} {
  //-{% for method in service.methods %}
  //-{% if method|methodIsUnary %}
  /// Synchronous. Unary.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}) throws -> {{ method|output }} {
    return try {{ .|call:file,service,method }}Base(channel)
      .run(request: request, metadata: metadata)
  }
  /// Asynchronous. Unary.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }},
                  completion: @escaping ({{ method|output }}?, CallResult) -> Void) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Base(channel)
      .start(request: request, metadata: metadata, completion: completion)
  }
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Base(channel)
      .start(request:request, metadata:metadata, completion:completion)
  }
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Base(channel)
       .start(metadata: metadata, completion: completion)
  }
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Base(channel)
      .start(metadata: metadata, completion: completion)
  }
  //-{% endif %}

  //-{% endfor %}
}

//-{% if generateTestStubs %}
class {{ .|serviceclass:file,service }}TestStub: ServiceClientTestStubBase, {{ .|serviceclass:file,service }} {
  //-{% for method in service.methods %}
  //-{% if method|methodIsUnary %}
  var {{ method|methodDescriptorName|lowercase }}Requests: [{{ method|input }}] = []
  var {{ method|methodDescriptorName|lowercase }}Responses: [{{ method|output }}] = []
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}) throws -> {{ method|output }} {
    {{ method|methodDescriptorName|lowercase }}Requests.append(request)
    defer { {{ method|methodDescriptorName|lowercase }}Responses.removeFirst() }
    return {{ method|methodDescriptorName|lowercase }}Responses.first!
  }
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: @escaping ({{ method|output }}?, CallResult) -> Void) throws -> {{ .|call:file,service,method }} {
    fatalError("not implemented")
  }
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  var {{ method|methodDescriptorName|lowercase }}Requests: [{{ method|input }}] = []
  var {{ method|methodDescriptorName|lowercase }}Calls: [{{ .|call:file,service,method }}] = []
  func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
      {{ method|methodDescriptorName|lowercase }}Requests.append(request)
    defer { {{ method|methodDescriptorName|lowercase }}Calls.removeFirst() }
    return {{ method|methodDescriptorName|lowercase }}Calls.first!
  }
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  var {{ method|methodDescriptorName|lowercase }}Calls: [{{ .|call:file,service,method }}] = []
  func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    defer { {{ method|methodDescriptorName|lowercase }}Calls.removeFirst() }
    return {{ method|methodDescriptorName|lowercase }}Calls.first!
  }
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  var {{ method|methodDescriptorName|lowercase }}Calls: [{{ .|call:file,service,method }}] = []
  func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    defer { {{ method|methodDescriptorName|lowercase }}Calls.removeFirst() }
    return {{ method|methodDescriptorName|lowercase }}Calls.first!
  }
  //-{% endif %}

  //-{% endfor %}
}
//-{% endif %}

//-{% endfor %}
