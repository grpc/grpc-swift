import GRPCCore
import GRPCNIOTransportHTTP2

extension RouteGuide {
  func runClient() async throws {
    try await withGRPCClient(
      transport: .http2NIOPosix(
        target: .ipv4(host: "127.0.0.1", port: 31415),
        transportSecurity: .plaintext
      )
    ) { client in
      let routeGuide = Routeguide_RouteGuide.Client(wrapping: client)
    }
  }
}
