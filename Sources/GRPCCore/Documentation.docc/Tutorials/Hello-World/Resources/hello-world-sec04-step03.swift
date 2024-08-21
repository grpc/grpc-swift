let greeter = Helloworld_GreeterClient(wrapping: client)
let reply = try await greeter.sayHello(.with { $0.name = self.name })
print(reply.message)
