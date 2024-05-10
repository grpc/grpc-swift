import ArgumentParser
import GRPCCore
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix
import NIOPosix

@testable import InteroperabilityTests

@main
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct InteroperabilityTestsExecutable {
  public static func main(_ arguments: [String]?) async {
    do {
      var command = try parseAsRoot()
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension InteroperabilityTestsExecutable: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "gRPC Swift Interoperability Runner",
    subcommands: [StartServer.self, ListTests.self]
  )

  struct StartServer: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Start the gRPC Swift interoperability test server."
    )

    @Option(help: "The port to listen on for new connections")
    var port: Int

    func run() async throws {
      var transportConfig = HTTP2ServerTransport.Posix.Config.defaults
      transportConfig.compression.enabledAlgorithms = .all
      let transport = HTTP2ServerTransport.Posix(
        address: .ipv4(host: "0.0.0.0", port: self.port),
        config: transportConfig
      )
      let server = GRPCServer(transport: transport, services: [TestService()])
      try await server.run()
    }
  }

  struct ListTests: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "List all interoperability test names."
    )

    func run() throws {
      InteroperabilityTestCase.allCases.forEach {
        print($0.name)
      }
    }
  }
}
