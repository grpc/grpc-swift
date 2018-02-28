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

/// Instantiate {{ .|serviceclass:file,service }}Impl, then call methods of this protocol to make API calls.
{{ access }} protocol {{ .|serviceclass:file,service }} {
  var channel: Channel { get }

  /// This metadata will be sent with all requests.
  var metadata: Metadata { get }

  /// This property allows the service host name to be overridden.
  /// For example, it can be used to make calls to "localhost:8080"
  /// appear to be to "example.com".
  var host : String { get }

  /// This property allows the service timeout to be overridden.
  var timeout : TimeInterval { get }
  
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

{{ access }} final class {{ .|serviceclass:file,service }}Client: {{ .|serviceclass:file,service }} {
  {{ access }} private(set) var channel: Channel

  {{ access }} var metadata : Metadata

  {{ access }} var host : String {
    get { return self.channel.host }
    set { self.channel.host = newValue }
  }

  {{ access }} var timeout : TimeInterval {
    get { return self.channel.timeout }
    set { self.channel.timeout = newValue }
  }

  /// Create a client.
  {{ access }} init(address: String, secure: Bool = true) {
    gRPC.initialize()
    channel = Channel(address:address, secure:secure)
    metadata = Metadata()
  }

  /// Create a client that makes secure connections with a custom certificate and (optional) hostname.
  {{ access }} init(address: String, certificates: String, host: String?) {
    gRPC.initialize()
    channel = Channel(address:address, certificates:certificates, host:host)
    metadata = Metadata()
  }

  //-{% for method in service.methods %}
  //-{% if method|methodIsUnary %}
  /// Synchronous. Unary.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}) throws -> {{ method|output }} {
    return try {{ .|call:file,service,method }}Impl(channel)
      .run(request: request, metadata: metadata)
  }
  /// Asynchronous. Unary.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }},
                  completion: @escaping ({{ method|output }}?, CallResult) -> Void) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Impl(channel)
      .start(request: request, metadata: metadata, completion: completion)
  }
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Impl(channel)
      .start(request:request, metadata:metadata, completion:completion)
  }
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Impl(channel)
       .start(metadata: metadata, completion: completion)
  }
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: ((CallResult) -> Void)?) throws -> {{ .|call:file,service,method }} {
    return try {{ .|call:file,service,method }}Impl(channel)
      .start(metadata: metadata, completion: completion)
  }
  //-{% endif %}

  //-{% endfor %}
}

//-{% if generateTestStubs %}
/// Simple fake implementation of {{ .|serviceclass:file,service }} that returns a previously-defined set of results
/// and stores request values passed into it for later verification.
/// Note: completion blocks are NOT called with this default implementation, and asynchronous unary calls are NOT implemented!
class {{ .|serviceclass:file,service }}TestStub: {{ .|serviceclass:file,service }} {
  var channel: Channel { fatalError("not implemented") }
  var metadata = Metadata()
  var host = ""
  var timeout: TimeInterval = 0
  
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
