import GRPCCore
import GRPCNIOTransportHTTP2

extension RouteGuide {
  func runServer() async throws {
    let features = try self.loadFeatures()
    let routeGuide = RouteGuideService(features: features)
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 31415),
        config: .defaults(transportSecurity: .plaintext)
      ),
      services: [routeGuide]
    )
  }
}
