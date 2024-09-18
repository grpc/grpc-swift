struct Greeter: Helloworld_GreeterServiceProtocol {
  func sayHello(
    request: ServerRequest.Single<Helloworld_HelloRequest>,
    context: ServerContext
  ) async throws -> ServerResponse.Single<Helloworld_HelloReply> {
    var reply = Helloworld_HelloReply()
    let recipient = request.message.name.isEmpty ? "stranger" : request.message.name
    reply.message = "Hello, \(recipient)"
    return ServerResponse.Single(message: reply)
  }
}
