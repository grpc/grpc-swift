struct Greeter: Helloworld_GreeterServiceProtocol {
  func sayHello(
    request: ServerRequest<Helloworld_HelloRequest>,
    context: ServerContext
  ) async throws -> ServerResponse<Helloworld_HelloReply> {
    var reply = Helloworld_HelloReply()
    let recipient = request.message.name.isEmpty ? "stranger" : request.message.name
    reply.message = "Hello, \(recipient)"
    return ServerResponse(message: reply)
  }

  func sayHelloAgain(
    request: ServerRequest<Helloworld_HelloRequest>,
    context: ServerContext
  ) async throws -> ServerResponse<Helloworld_HelloReply> {
    var reply = Helloworld_HelloReply()
    let recipient = request.message.name.isEmpty ? "stranger" : request.message.name
    reply.message = "Hello again, \(recipient)"
    return ServerResponse(message: reply)
  }
}
