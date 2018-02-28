{{ access }} protocol {{ .|session:file,service,method }}: ServerSessionUnary { }

fileprivate final class {{ .|session:file,service,method }}Impl: ServerSessionUnaryImpl<{{ method|input }}, {{ method|output }}>, {{ .|session:file,service,method }} { }

//-{% if generateTestStubs %}
class {{ .|session:file,service,method }}TestStub: ServerSessionUnaryTestStub, {{ .|session:file,service,method }} { }
//-{% endif %}
