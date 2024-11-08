import GRPCCore
import GRPCNIOTransportHTTP2

extension RouteGuide {
  func runClient() async throws {
    let client = try GRPCClient(
      transport: .http2NIOPosix(
        target: .ipv4(host: "127.0.0.1", port: 31415),
        config: .defaults(transportSecurity: .plaintext)
      )
    )

    async let _ = client.run()

    let routeGuide = Routeguide_RouteGuideClient(wrapping: client)
  }
}
