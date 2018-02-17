//-{% for service in file.services %}

/// Type for errors thrown from generated client code.
{{ access }} enum {{ .|clienterror:file,service }} : Error {
  case endOfStream
  case invalidMessageReceived
  case error(c: CallResult)
}

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
/// Call methods of this class to make API calls.
{{ access }} final class {{ .|serviceclass:file,service }} {
  public private(set) var channel: Channel

  /// This metadata will be sent with all requests.
  {{ access }} var metadata : Metadata

  /// This property allows the service host name to be overridden.
  /// For example, it can be used to make calls to "localhost:8080"
  /// appear to be to "example.com".
  {{ access }} var host : String {
    get {
      return self.channel.host
    }
    set {
      self.channel.host = newValue
    }
  }

  /// This property allows the service timeout to be overridden.
  {{ access }} var timeout : TimeInterval {
    get {
      return self.channel.timeout
    }
    set {
      self.channel.timeout = newValue
    }
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
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }})
    throws
    -> {{ method|output }} {
      return try {{ .|call:file,service,method }}(channel).run(request:request, metadata:metadata)
  }
  /// Asynchronous. Unary.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }},
                  completion: @escaping ({{ method|output }}?, CallResult)->())
    throws
    -> {{ .|call:file,service,method }} {
      return try {{ .|call:file,service,method }}(channel).start(request:request,
                                                 metadata:metadata,
                                                 completion:completion)
  }
  //-{% endif %}
  //-{% if method|methodIsServerStreaming %}
  /// Asynchronous. Server-streaming.
  /// Send the initial message.
  /// Use methods on the returned object to get streamed responses.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(_ request: {{ method|input }}, completion: @escaping (CallResult)->())
    throws
    -> {{ .|call:file,service,method }} {
      return try {{ .|call:file,service,method }}(channel).start(request:request, metadata:metadata, completion:completion)
  }
  //-{% endif %}
  //-{% if method|methodIsClientStreaming %}
  /// Asynchronous. Client-streaming.
  /// Use methods on the returned object to stream messages and
  /// to close the connection and wait for a final response.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: @escaping (CallResult)->())
    throws
    -> {{ .|call:file,service,method }} {
      return try {{ .|call:file,service,method }}(channel).start(metadata:metadata, completion:completion)
  }
  //-{% endif %}
  //-{% if method|methodIsBidiStreaming %}
  /// Asynchronous. Bidirectional-streaming.
  /// Use methods on the returned object to stream messages,
  /// to wait for replies, and to close the connection.
  {{ access }} func {{ method|methodDescriptorName|lowercase }}(completion: @escaping (CallResult)->())
    throws
    -> {{ .|call:file,service,method }} {
      return try {{ .|call:file,service,method }}(channel).start(metadata:metadata, completion:completion)
  }
  //-{% endif %}
  //-{% endfor %}
}
//-{% endfor %}
