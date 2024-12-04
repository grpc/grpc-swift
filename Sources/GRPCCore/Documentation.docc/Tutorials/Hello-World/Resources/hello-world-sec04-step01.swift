struct Greeter: Helloworld_Greeter.SimpleServiceProtocol {
  func sayHello(
    request: Helloworld_HelloRequest,
    context: ServerContext
  ) async throws -> Helloworld_HelloReply {
    var reply = Helloworld_HelloReply()
    let recipient = request.message.name.isEmpty ? "stranger" : request.message.name
    reply.message = "Hello, \(recipient)"
    return reply
  }
}
